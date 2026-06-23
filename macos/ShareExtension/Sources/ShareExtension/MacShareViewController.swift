import AppKit
import Foundation
import UniformTypeIdentifiers
import os.log

private let socketRelativePath = "is.sock"
private let log = OSLog(subsystem: "net.boldman.ausearch.share-extension", category: "ShareExtension")

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

    override func beginRequest(with context: NSExtensionContext) {
        super.beginRequest(with: context)
        self.extensionContextRef = context
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        
        os_log("ShareExtension viewDidAppear — Ready to safely load items", log: log, type: .info)
        
        // Diagnostic: log sandbox context for debugging file access issues
        let homeDir = NSHomeDirectory()
        let tmpDir = NSTemporaryDirectory()
        let docDirs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? "?"
        os_log("[SHARE_EXT] viewDidAppear context: home=%{public}@ tmp=%{public}@ documents=%{public}@",
               log: log, type: .info, homeDir, tmpDir, docDirs)
        
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
        
        Task {
            await processExtensionItems(items, with: context)
        }
    }

    private func processExtensionItems(_ items: [NSExtensionItem], with context: NSExtensionContext) async {
        if await tryProcessFileExtensionItems(items, with: context) {
            return
        } else if await tryProcessImageExtensionItems(items, with: context) {
            return
        } else if await tryProcessURLExtensionItems(items, with: context) {
            return
        } else if await tryProcessRichTextExtensionItems(items, with: context) {
            return
        } else if await tryProcessPlainTextExtensionItems(items, with: context) {
            return
        }
    }

    private func tryProcessFileExtensionItems(
        _ items: [NSExtensionItem], with context: NSExtensionContext
    ) async -> Bool {
        var fileProviders: [NSItemProvider] = []
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    fileProviders.append(provider)
                }
            }
        }
        let fileURLs = await withTaskGroup(of: Optional<URL>.self, returning: [URL].self) { group in
            for provider in fileProviders {
                group.addTask {
                    do {
                        let dataType = provider.registeredTypeIdentifiers
                            .filter({ $0 != UTType.fileURL.identifier && $0 != UTType.url.identifier })
                            .first ?? UTType.data.identifier
                        let (url, isInPlace) = try await provider.loadInPlaceFileRepresentation(
                            forTypeIdentifier: dataType)
                        // Debug log
                        let fm = FileManager.default
                        let attrs = try? fm.attributesOfItem(atPath: url.path)
                        let isReadable = fm.isReadableFile(atPath: url.path)
                        let isWritable = fm.isWritableFile(atPath: url.path)
                        let fileExists = fm.fileExists(atPath: url.path)
                        let isDirectory: Bool = {
                            var isDir: ObjCBool = false
                            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
                        }()
                        let posixPermissions = (attrs?[.posixPermissions] as? NSNumber).map {
                            String(format: "0o%o", $0.uint16Value) } ?? "?"
                        let ownerAccountID = attrs?[.ownerAccountID] as? NSNumber
                        let fileSize = attrs?[.size] as? NSNumber
                        os_log("[SHARE_EXT] url=%{public}@ size=%{public}@ isInPlace=%{bool}d exists=%{bool}d isDir=%{bool}d readable=%{bool}d writable=%{bool}d mode=%{public}@ owner=%{public}@ registeredTypes=%{public}@",
                            log: log, type: .debug,
                            url.path, String(describing: fileSize), isInPlace,
                            fileExists, isDirectory, isReadable, isWritable,
                            posixPermissions, String(describing: ownerAccountID), String(describing: provider.registeredTypeIdentifiers))
                        if !isInPlace {
                            do {
                                let containerURL =
                                    FileManager.default.urls(
                                        for: .documentDirectory, in: .userDomainMask
                                    ).first
                                    ?? FileManager.default.temporaryDirectory
                                let destination = containerURL.appendingPathComponent(
                                    url.lastPathComponent)
                                try FileLinker.createHardLinkOrCopy(from: url, to: destination)
                                return destination
                            } catch {
                                os_log("Failed to create hard link or copy for %{public}@",
                                    log: log, type: .info, url.path)
                                return url
                            }
                        }
                        return url
                    } catch {
                        os_log("Failed to load file URL: %{public}@",
                        log: log, type: .error, error.localizedDescription)
                        return nil
                    }
                }
            }
            var urls: [URL] = []
            for await url in group {
                if let url = url {
                    urls.append(url)
                }
            }
            return urls
        }
        if fileURLs.isEmpty {
            os_log("No file URLs found in extension items", log: log, type: .info)
            return false
        }
        self.stashBatchFilePayload(fileURLs, with: context)
        return true
    }

    private func tryProcessImageExtensionItems(
        _ items: [NSExtensionItem], with context: NSExtensionContext
    ) async -> Bool {
        var imageProvider: NSItemProvider? = nil
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    imageProvider = provider
                    break
                }
            }
            if imageProvider != nil {
                break
            }
        }
        guard let imageProvider = imageProvider else {
            return false
        }
        do {
            let url = try await imageProvider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier)
            self.stashFilePayload(url, with: context)
        } catch {
            os_log("Failed to load & stash image: %{public}@", log: log, type: .error, error.localizedDescription)
        }
        return true
    }

    private func tryProcessURLExtensionItems(
        _ items: [NSExtensionItem], with context: NSExtensionContext
    ) async -> Bool {
        var urlProvider: NSItemProvider? = nil
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    urlProvider = provider
                    break
                }
            }
            if urlProvider != nil { break }
        }
        guard let provider = urlProvider else { return false }

        do {
            let raw: NSSecureCoding = try await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
            let urlString: String
            if let url = raw as? URL {
                urlString = url.absoluteString
            } else if let data = raw as? Data, let str = String(data: data, encoding: .utf8) {
                urlString = str
            } else {
                os_log("[SHARE_EXT] URL item resolved to unexpected type: %{public}@",
                       log: log, type: .error, String(describing: type(of: raw)))
                return false
            }
            if let scheme = URL(string: urlString)?.scheme, ["http", "https"].contains(scheme) {
                os_log("[SHARE_EXT] Web URL detected — stashing as link", log: log, type: .info)
                stashLinkPayload(urlString, with: context)
            } else {
                os_log("[SHARE_EXT] Non-web URL — stashing as text", log: log, type: .info)
                stashTextPayload(urlString, with: context)
            }
            return true
        } catch {
            os_log("[SHARE_EXT] Failed to load URL item: %{public}@",
                   log: log, type: .error, error.localizedDescription)
            return false
        }
    }

    private func tryProcessRichTextExtensionItems(
        _ items: [NSExtensionItem], with context: NSExtensionContext
    ) async -> Bool {
        let richTypes = [
            UTType.rtf.identifier,
            UTType.html.identifier,
            "com.apple.flat-rtfd",
        ]
        var richTextProvider: NSItemProvider? = nil
        var matchedType: String = ""
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                for richType in richTypes {
                    if provider.hasItemConformingToTypeIdentifier(richType) {
                        richTextProvider = provider
                        matchedType = richType
                        break
                    }
                }
                if richTextProvider != nil { break }
            }
            if richTextProvider != nil { break }
        }
        guard let provider = richTextProvider else { return false }

        do {
            let raw: NSSecureCoding = try await provider.loadItem(forTypeIdentifier: matchedType)
            if let attributed = raw as? NSAttributedString {
                convertAndStashRichText(attributed, with: context)
            } else if let data = raw as? Data,
                      let attributed = try? NSAttributedString(data: data, options: [:], documentAttributes: nil) {
                convertAndStashRichText(attributed, with: context)
            } else if let string = raw as? String,
                      let data = string.data(using: .utf8),
                      let attributed = try? NSAttributedString(data: data, options: [:], documentAttributes: nil) {
                convertAndStashRichText(attributed, with: context)
            } else {
                os_log("[SHARE_EXT] Rich text item resolved to unexpected type: %{public}@",
                       log: log, type: .error, String(describing: type(of: raw)))
                return false
            }
            return true
        } catch {
            os_log("[SHARE_EXT] Failed to load rich text item: %{public}@",
                   log: log, type: .error, error.localizedDescription)
            return false
        }
    }

    private func tryProcessPlainTextExtensionItems(
        _ items: [NSExtensionItem], with context: NSExtensionContext
    ) async -> Bool {
        var plainTextProvider: NSItemProvider? = nil
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    // Skip providers that are backed by an actual file — those are
                    // handled by tryProcessFileExtensionItems.
                    if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
                        continue
                    }
                    plainTextProvider = provider
                    break
                }
            }
            if plainTextProvider != nil { break }
        }
        guard let provider = plainTextProvider else {
            // Also check attributedTitle/attributedContentText on items (e.g. Notes.app shares).
            for item in items {
                if tryProcessAttributedTitleOrContent(item: item, with: context) {
                    return true
                }
            }
            return false
        }


        do {
            let raw: NSSecureCoding = try await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier)
            let text: String
            if let string = raw as? String {
                text = string
            } else if let data = raw as? Data, let decoded = String(data: data, encoding: .utf8) {
                text = decoded
            } else {
                os_log("[SHARE_EXT] Plain text item resolved to unexpected type: %{public}@",
                       log: log, type: .error, String(describing: type(of: raw)))
                return false
            }
            stashTextPayload(text, with: context)
            return true
        } catch {
            os_log("[SHARE_EXT] Failed to load plain text item: %{public}@",
                   log: log, type: .error, error.localizedDescription)
            return false
        }
    }

    private func tryProcessAttributedTitleOrContent(item: NSExtensionItem, with context: NSExtensionContext) -> Bool {
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
            return true
        }
        return false
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

    private func stashLinkPayload(_ urlString: String, with context: NSExtensionContext) {
        os_log("Stashing link payload: %{public}@", log: log, type: .info, urlString)
        let body: [String: String] = [
            "type": "link",
            "content": urlString
        ]
        sendStashRequest(body) { [weak self] success in
            if success {
                os_log("Link stash succeeded — completing extension", log: log, type: .info)
                self?.completeRequest(with: context)
            } else {
                os_log("Link stash failed — cancelling extension", log: log, type: .error)
                self?.cancel(with: context)
            }
        }
    }

    private func stashFilePayload(_ url: URL, with context: NSExtensionContext) {
        os_log("[SHARE_EXT] Stashing single file: path=%{public}@ filename=%{public}@",
               log: log, type: .info, url.path, url.lastPathComponent)
        let files: [[String: String]] = [
            ["file_path": url.path, "filename": url.lastPathComponent]
        ]
        let body: [String: Any] = [
            "type": "file",
            "files": files
        ]
        sendStashRequest(body) { [weak self] success in
            if success {
                os_log("[SHARE_EXT] File stash succeeded — completing extension", log: log, type: .info)
                self?.completeRequest(with: context)
            } else {
                os_log("[SHARE_EXT] File stash FAILED — cancelling extension for path=%{public}@",
                       log: log, type: .error, url.path)
                self?.cancel(with: context)
            }
        }
    }

    private func stashBatchFilePayload(_ urls: [URL], with context: NSExtensionContext) {
        let fileList: [[String: String]] = urls.map { url in
            ["file_path": url.path, "filename": url.lastPathComponent]
        }
        os_log("[SHARE_EXT] Stashing batch: count=%d paths=%{public}@",
               log: log, type: .info, urls.count, fileList.map { $0["file_path"] ?? "?" }.joined(separator: " | "))
        let body: [String: Any] = [
            "type": "file",
            "files": fileList
        ]
        sendStashRequest(body) { [weak self] success in
            if success {
                os_log("[SHARE_EXT] Batch file stash succeeded — completing extension", log: log, type: .info)
                self?.completeRequest(with: context)
            } else {
                os_log("[SHARE_EXT] Batch file stash FAILED — cancelling extension for %d files",
                       log: log, type: .error, urls.count)
                self?.cancel(with: context)
            }
        }
    }

    private func sendStashRequest(_ body: [String: Any], completion: @escaping (Bool) -> Void) {
        let filePaths = (body["files"] as? [[String: String]])?.compactMap { $0["file_path"] }.joined(separator: " | ") ?? "?"
        os_log("[SHARE_EXT] Sending stash request to UDS: type=%{public}@ paths=%{public}@",
               log: log, type: .info, body["type"] as? String ?? "?", filePaths)
        httpClient.postJSON(path: "/api/instant-share/v1/qr-trigger", body: body) { result in
            switch result {
            case .success(let (data, statusCode)):
                let success = statusCode == 201
                let preview = String(data: data, encoding: .utf8) ?? "<binary>"
                if success {
                    os_log("[SHARE_EXT] Stash response OK (status=%d, %d bytes): %{public}@",
                           log: log, type: .info, statusCode, data.count,
                           String(preview.prefix(200)))
                } else {
                    os_log("[SHARE_EXT] Stash response FAILED (status=%d, %d bytes): %{public}@%{public}@",
                           log: log, type: .error, statusCode, data.count,
                           String(preview.prefix(500)),
                           preview.count > 500 ? " [TRUNCATED]" : "")
                }
                completion(success)
            case .failure(let error):
                let nsError = error as NSError
                os_log("[SHARE_EXT] Stash request FAILED: domain=%{public}@ code=%d description=%{public}@ paths=%{public}@",
                       log: log, type: .error, nsError.domain, nsError.code, error.localizedDescription, filePaths)
                completion(false)
            }
        }
    }

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
