import AppKit
import Foundation
import UniformTypeIdentifiers
import os.log

private let socketRelativePath = "is.sock"
private let log = OSLog(subsystem: "net.boldman.ausearch.share-extension", category: "ShareExtension")

// 1. 改为继承自 NSViewController
class MacShareViewController: NSViewController {
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
        self.view = NSView()
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
        // Phase 1: Scan for rich text or plain text (takes priority over files)
        for item in items {
            let hasTitle = item.attributedTitle?.length ?? 0 > 0
            let hasContent = item.attributedContentText?.length ?? 0 > 0
            
            if hasTitle || hasContent {
                let combined = NSMutableAttributedString()
                if let title = item.attributedTitle, title.length > 0 {
                    os_log("Found attributedTitle on extension item (%d chars)", log: log, type: .info, title.length)
                    combined.append(title)
                }
                if let content = item.attributedContentText, content.length > 0 {
                    if combined.length > 0 {
                        combined.append(NSAttributedString(string: "\n\n"))
                    }
                    os_log("Found attributedContentText on extension item (%d chars)", log: log, type: .info, content.length)
                    combined.append(content)
                }
                convertAndStashRichText(combined, with: context)
                return
            }
            
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                let richTextTypes = [UTType.rtf.identifier, UTType.html.identifier, "com.apple.flat-rtfd"]
                for richType in richTextTypes {
                    if provider.hasItemConformingToTypeIdentifier(richType) {
                        os_log("Matched rich text type: %{public}@", log: log, type: .info, richType)
                        provider.loadItem(forTypeIdentifier: richType, options: nil) { [weak self] data, error in
                            if let error = error {
                                os_log("Failed to load rich text: %{public}@", log: log, type: .error, error.localizedDescription)
                                self?.cancel(with: context)
                                return
                            }
                            self?.processRichTextData(data, type: richType, with: context)
                        }
                        return
                    }
                }
                
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    os_log("Matched text attachment", log: log, type: .info)
                    provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] data, error in
                        if let error = error {
                            os_log("Failed to load text: %{public}@", log: log, type: .error, error.localizedDescription)
                            self?.cancel(with: context)
                            return
                        }
                        os_log("Type of data: %{public}@", log: log, type: .info, String(describing: type(of: data)))
                        guard let text = data as? String ?? (data as? Data).flatMap({ String(data: $0, encoding: .utf8) }) else {
                            os_log("Failed to load text: data is neither String nor UTF-8 Data", log: log, type: .error)
                            self?.cancel(with: context)
                            return
                        }
                        self?.stashTextPayload(text, with: context)
                    }
                    return
                }
            }
        }
        
        // Phase 2: No text found — collect all file URLs from all items
        var fileURLs: [(url: URL, isInPlace: Bool)] = []
        var fileLoadCount = 0
        var totalProviders = 0
        let loadGroup = DispatchGroup()
        let loadLock = NSLock()
        
        // Count total file providers across all items
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
                    totalProviders += 1
                }
            }
        }
        
        if totalProviders == 0 {
            os_log("No supported attachments found — cancelling", log: log, type: .error)
            cancel(with: context)
            return
        }
        
        os_log("Collecting %d file URLs from extension items", log: log, type: .info, totalProviders)
        
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                guard provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) else { continue }
                
                loadGroup.enter()
                provider.loadInPlaceFileRepresentation(forTypeIdentifier: UTType.data.identifier) { (originalURL, isInPlace, error) in
                    defer { loadGroup.leave() }
                    
                    if let error = error {
                        os_log("Failed to get in-place URL: %{public}@", log: log, type: .error, error.localizedDescription)
                        return
                    }
                    
                    guard let safeURL = originalURL else {
                        os_log("Original URL is nil", log: log, type: .error)
                        return
                    }
                    
                    loadLock.lock()
                    fileURLs.append((url: safeURL, isInPlace: isInPlace))
                    fileLoadCount += 1
                    
                    let attrs = try? FileManager.default.attributesOfItem(atPath: safeURL.path)
                    os_log("File %d/%d: url=%{public}@ size=%{public}@ isInPlace=%{bool}d",
                           log: log, type: .info, fileLoadCount, totalProviders,
                           safeURL.path, String(describing: attrs?[.size]), isInPlace)
                    loadLock.unlock()
                }
            }
        }
        
        // Wait for all file loads to complete, then stash
        loadGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            if fileURLs.isEmpty {
                os_log("No file URLs resolved — cancelling", log: log, type: .error)
                self.cancel(with: context)
                return
            }
            
            if !fileURLs.allSatisfy({ $0.isInPlace }) {
                os_log("Non-in-place files detected — using hard links for batch", log: log, type: .info)
            }
            
            // Resolve URLs: in-place ones use original; non-in-place get hard links
            let resolvedURLs: [URL] = fileURLs.map { entry in
                if entry.isInPlace {
                    return entry.url
                }
                return self.createHardLink(for: entry.url) ?? entry.url
            }
            
            if resolvedURLs.count == 1 {
                self.stashFilePayload(resolvedURLs[0], with: context)
            } else {
                self.stashBatchFilePayload(resolvedURLs, with: context)
            }
        }
    }

    private func convertAndStashRichText(_ attributedString: NSAttributedString, with context: NSExtensionContext) {
        // Convert to HTML
        let htmlData = try? attributedString.data(
            from: NSRange(location: 0, length: attributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        )
        
        guard let htmlContent = htmlData, let htmlString = String(data: htmlContent, encoding: .utf8) else {
            os_log("Failed to convert NSAttributedString to HTML", log: log, type: .error)
            cancel(with: context)
            return
        }
        
        os_log("Stashing HTML payload (%d chars)", log: log, type: .info, htmlString.count)
        stashHTMLPayload(htmlString, with: context)
    }
    
    private func processRichTextData(_ data: Any?, type: String, with context: NSExtensionContext) {
        var attributedString: NSAttributedString?
        
        if let attributed = data as? NSAttributedString {
            attributedString = attributed
        } else if let data = data as? Data {
            attributedString = try? NSAttributedString(data: data, options: [:], documentAttributes: nil)
        } else if let string = data as? String, let data = string.data(using: .utf8) {
            attributedString = try? NSAttributedString(data: data, options: [:], documentAttributes: nil)
        }
        
        guard let finalAttributedString = attributedString else {
            os_log("Failed to convert data to NSAttributedString", log: log, type: .error)
            cancel(with: context)
            return
        }
        
        // Convert to HTML
        let htmlData = try? finalAttributedString.data(
            from: NSRange(location: 0, length: finalAttributedString.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        )
        
        guard let htmlContent = htmlData, let htmlString = String(data: htmlContent, encoding: .utf8) else {
            os_log("Failed to convert NSAttributedString to HTML", log: log, type: .error)
            cancel(with: context)
            return
        }
        
        os_log("Stashing HTML payload (%d chars)", log: log, type: .info, htmlString.count)
        stashHTMLPayload(htmlString, with: context)
    }
    
    private func stashHTMLPayload(_ html: String, with context: NSExtensionContext) {
        os_log("Stashing HTML payload (%d chars)", log: log, type: .info, html.count)
        let body: [String: String] = [
            "type": "html",
            "content": html
        ]
        sendStashRequest(body) { [weak self] success in
            if success {
                os_log("HTML stash succeeded — completing extension", log: log, type: .info)
                self?.completeRequest(with: context)
            } else {
                os_log("HTML stash failed — cancelling extension", log: log, type: .error)
                self?.cancel(with: context)
            }
        }
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
        let hardLinkURL = createHardLink(for: originalURL)
        if let url = hardLinkURL {
            stashFilePayload(url, with: context)
        } else {
            stashFilePayload(originalURL, with: context)
        }
    }

    private func createHardLink(for originalURL: URL) -> URL? {
        let containerURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let hardLinkURL = containerURL.appendingPathComponent(originalURL.lastPathComponent)
        
        do {
            if FileManager.default.fileExists(atPath: hardLinkURL.path) {
                try FileManager.default.removeItem(at: hardLinkURL)
            }
            try FileManager.default.linkItem(at: originalURL, to: hardLinkURL)
            os_log("Hard link created: %{public}@", log: log, type: .info, hardLinkURL.path)
            return hardLinkURL
        } catch {
            os_log("Failed to create hard link: %{public}@", log: log, type: .error, error.localizedDescription)
            return nil
        }
    }

    private func stashFilePayload(_ url: URL, with context: NSExtensionContext) {
        os_log("Stashing file payload: %{public}@", log: log, type: .info, url.path)
        let files: [[String: String]] = [
            ["file_path": url.path, "filename": url.lastPathComponent]
        ]
        let body: [String: Any] = [
            "type": "file",
            "files": files
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

    private func stashBatchFilePayload(_ urls: [URL], with context: NSExtensionContext) {
        os_log("Stashing batch file payload: %d files", log: log, type: .info, urls.count)
        let files: [[String: String]] = urls.map { url in
            ["file_path": url.path, "filename": url.lastPathComponent]
        }
        let body: [String: Any] = [
            "type": "file",
            "files": files
        ]
        sendStashRequest(body) { [weak self] success in
            if success {
                os_log("Batch file stash succeeded — completing extension", log: log, type: .info)
                self?.completeRequest(with: context)
            } else {
                os_log("Batch file stash failed — cancelling extension", log: log, type: .error)
                self?.cancel(with: context)
            }
        }
    }

    private func sendStashRequest(_ body: [String: Any], completion: @escaping (Bool) -> Void) {
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
