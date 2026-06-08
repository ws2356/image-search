import AppKit
import Foundation
import UniformTypeIdentifiers
import os.log

private let socketRelativePath = "is.sock"
private let log = OSLog(subsystem: "net.boldman.ausearch.share-extension", category: "ShareExtension")

// 1. 改为继承自 NSViewController
class MacShareViewController: NSViewController {
    private let spinner = NSProgressIndicator()
    private var extensionContextRef: NSExtensionContext?

    private lazy var httpClient: UDSHTTPClient = {
        guard let containerURL = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else {
            os_log("Failed to resolve container URL", log: log, type: .error)
            return UDSHTTPClient(socketPath: "")
        }
        let fullPath = containerURL.appendingPathComponent(socketRelativePath).path
        os_log("UDS endpoint: %{public}@", log: log, type: .info, fullPath)
        return UDSHTTPClient(socketPath: fullPath)
    }()


    override func loadView() {
        // 设置一个合适的大小（类似于系统原装输入框面板的体量，或者更精简一点）
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 120))
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 16
        // 使用自带的材质特效或者圆角半透明，让它看起来很原生
        containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
        
        // 配置菊花 (Progress Indicator)
        spinner.style = .spinning
        spinner.controlSize = .regular // 使用标准大小的菊花
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.isDisplayedWhenStopped = false
        
        containerView.addSubview(spinner)
        
        // 将菊花居中约束
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 32),
            spinner.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        self.view = containerView
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // 让宿主窗口去除多余的阴影和边框，只保留我们自己画的圆角面板
        if let window = self.view.window {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
        }
        // 让菊花开始转动
        spinner.startAnimation(nil)
    }

    // 2. beginRequest 只负责存下 context，绝不在这里调用 loadItem
    override func beginRequest(with context: NSExtensionContext) {
        super.beginRequest(with: context)
        self.extensionContextRef = context
    }

// 3. 此时 Finder 的 UI 握手已彻底结束，主线程恢复响应！开始安全地拉取数据
    override func viewDidAppear() {
        super.viewDidAppear()
        
        os_log("ShareExtension viewDidAppear — Ready to safely load items", log: log, type: .info)
        
        guard let context = self.extensionContextRef else {
            os_log("No extensionContext available", log: log, type: .error)
            return
        }

        let items = context.inputItems as? [NSExtensionItem] ?? []
        os_log("Received %d extension items", log: log, type: .info, items.count)
        
        if items.isEmpty {
            os_log("No extension items — cancelling", log: log, type: .error)
            self.cancel(with: context)
            return
        }
        
        processExtensionItems(items, with: context)
    }

    private func processExtensionItems(_ items: [NSExtensionItem], with context: NSExtensionContext) {
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                // 1. 处理文本（保持不变）
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    os_log("Matched text attachment", log: log, type: .info)
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] data, error in
                        if error != nil {
                            self?.cancel(with: context)
                            return
                        }
                        guard let text = data as? String else { return }
                        self?.stashTextPayload(text, with: context)
                    }
                    return
                }
                
                // 2. 核心优化：针对文件/图片，开启【零拷贝】模式
                if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
                    os_log("Matched file URL (Zero-Copy Mode)", log: log, type: .info)
                    
                    // 使用 loadInPlaceFileRepresentation 明确告知系统：我不需要拷贝，只要原位访问权限
                    provider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.data.identifier) { [weak self] (originalURL, isInPlace, error) in
                        if let error = error {
                            os_log("Failed to get in-place URL: %{public}@", log: log, type: .error, error.localizedDescription)
                            self?.cancel(with: context)
                            return
                        }
                        
                        guard let safeURL = originalURL else {
                            os_log("Original URL is nil", log: log, type: .error)
                            self?.cancel(with: context)
                            return
                        }

                        let attrs = try? FileManager.default.attributesOfItem(
                            atPath: safeURL.path
                        )
                        os_log("url=%{public}@ size=%{public}@", log: log, type: .info, safeURL.path, String(describing: attrs?[.size]))
                        let values = try? safeURL.resourceValues(forKeys: [
                            .contentTypeKey,
                            .fileSizeKey,
                            .isAliasFileKey])
                        os_log("url=%{public}@ contentType=%{public}@ size=%{public}@ isAlias=%{public}@", log: log, type: .info, safeURL.path, String(describing: values?.contentType), String(describing: values?.fileSize), String(describing: values?.isAliasFile))
                                        
                        let isSecurityScoped = safeURL.startAccessingSecurityScopedResource()
                        
                        os_log("Successfully grabbed original path: %{public}@, isInPlace: %{bool}d", log: log, type: .info, safeURL.path, isInPlace)
                        
                        if isInPlace {
                            os_log("In-place file — sending original URL directly", log: log, type: .info)
                            self?.stashFilePayload(safeURL, with: context)
                        } else {
                            os_log("Non-in-place file — creating hard link in sandbox", log: log, type: .info)
                            self?.createHardLinkAndSend(originalURL: safeURL, with: context)
                        }
                        
                        if isSecurityScoped {
                            safeURL.stopAccessingSecurityScopedResource()
                        }
                    }
                    return
                }
            }
        }
        os_log("No supported attachments found — cancelling", log: log, type: .error)
        cancel(with: context)
    }

    private func stashTextPayload(_ text: String, with context: NSExtensionContext) {
        os_log("Stashing text payload (%d chars)", log: log, type: .info, text.count)
        let body: [String: String] = [
            "type": "text",
            "content": text
        ]
        sendStashRequest(body) { [weak self] success in
            if success {
                os_log("Text stash succeeded — completing extension", log: log, type: .info)
                self?.completeRequest(with: context)
            } else {
                os_log("Text stash failed — cancelling extension", log: log, type: .error)
                self?.cancel(with: context)
            }
        }
    }

    private func createHardLinkAndSend(originalURL: URL, with context: NSExtensionContext) {
        let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let hardLinkURL = containerURL.appendingPathComponent(originalURL.lastPathComponent)
        
        do {
            if FileManager.default.fileExists(atPath: hardLinkURL.path) {
                try FileManager.default.removeItem(at: hardLinkURL)
            }
            try FileManager.default.linkItem(at: originalURL, to: hardLinkURL)
            os_log("Hard link created: %{public}@", log: log, type: .info, hardLinkURL.path)
            stashFilePayload(hardLinkURL, with: context)
        } catch {
            os_log("Failed to create hard link: %{public}@ — falling back to original URL", log: log, type: .error, error.localizedDescription)
            stashFilePayload(originalURL, with: context)
        }
    }

    private func stashFilePayload(_ url: URL, with context: NSExtensionContext) {
        os_log("Stashing file payload: %{public}@", log: log, type: .info, url.path)
        let body: [String: String] = [
            "type": "image",
            "file_path": url.path,
            "filename": url.lastPathComponent
        ]
        sendStashRequest(body) { [weak self] success in
            if success {
                os_log("File stash succeeded — completing extension", log: log, type: .info)
                self?.completeRequest(with: context)
            } else {
                os_log("File stash failed — cancelling extension", log: log, type: .error)
                self?.cancel(with: context)
            }
        }
    }

    private func sendStashRequest(_ body: [String: String], completion: @escaping (Bool) -> Void) {
        os_log("Sending stash request via async-http-client over UDS", log: log, type: .info)
        httpClient.postJSON(path: "/api/instant-share/v1/qr-trigger", body: body) { result in
            switch result {
            case .success(let (data, statusCode)):
                let success = statusCode == 201
                let preview = String(data: data, encoding: .utf8) ?? "<binary>"
                os_log("Stash response (status=%d, success=%{bool}d, %d bytes): %{public}@",
                       log: log, type: .info, statusCode, success, data.count,
                       String(preview.prefix(200)))
                completion(success)
            case .failure(let error):
                os_log("Stash request failed: %{public}@", log: log, type: .error, error.localizedDescription)
                completion(false)
            }
        }
    }

    // 4. 显式传入并使用当前生命周期块内的 context
    private func completeRequest(with context: NSExtensionContext) {
        os_log("Completing extension request — success", log: log, type: .info)
        context.completeRequest(returningItems: nil, completionHandler: nil)
    }

    private func cancel(with context: NSExtensionContext) {
        os_log("Extension cancelled", log: log, type: .info)
        context.cancelRequest(withError: NSError(
            domain: "ShareExtension",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "User canceled"]
        ))
    }
}