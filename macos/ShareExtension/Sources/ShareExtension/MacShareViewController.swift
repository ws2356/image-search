import AppKit
import Social
import os.log

private let socketRelativePath = "is.sock"
private let log = OSLog(subsystem: "net.boldman.ausearch.share-extension", category: "ShareExtension")

class MacShareViewController: SLComposeServiceViewController {

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

    override func viewDidAppear() {
        super.viewDidAppear()
        os_log("ShareExtension activated", log: log, type: .info)
        guard let context = extensionContext else {
            os_log("No extensionContext — cancelling", log: log, type: .error)
            cancel()
            return
        }
        let items = context.inputItems as? [NSExtensionItem] ?? []
        os_log("Received %d extension items", log: log, type: .info, items.count)
        processExtensionItems(items)
    }

    private func processExtensionItems(_ items: [NSExtensionItem]) {
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
                    os_log("Matched text attachment", log: log, type: .info)
                    provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { [weak self] data, error in
                        if let error = error {
                            os_log("Failed to load text: %{public}@", log: log, type: .error, error.localizedDescription)
                            self?.cancel()
                            return
                        }
                        guard let text = data as? String else { return }
                        os_log("Loaded text payload (%d chars)", log: log, type: .info, text.count)
                        self?.stashTextPayload(text)
                    }
                    return
                }
                if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                    os_log("Matched file URL attachment", log: log, type: .info)
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { [weak self] data, error in
                        if let error = error {
                            os_log("Failed to load file URL: %{public}@", log: log, type: .error, error.localizedDescription)
                            self?.cancel()
                            return
                        }
                        if let url = data as? URL {
                            os_log("Loaded file URL: %{public}@", log: log, type: .info, url.path)
                            self?.stashFilePayload(url)
                        } else if let path = data as? String {
                            os_log("Loaded file path: %{public}@", log: log, type: .info, path)
                            self?.stashFilePayload(URL(fileURLWithPath: path))
                        }
                    }
                    return
                }
            }
        }
        os_log("No supported attachments found — cancelling", log: log, type: .error)
        cancel()
    }

    private func stashTextPayload(_ text: String) {
        os_log("Stashing text payload (%d chars)", log: log, type: .info, text.count)
        let body: [String: String] = [
            "type": "text",
            "content": text
        ]
        sendStashRequest(body) { [weak self] success in
            if success {
                os_log("Text stash succeeded — completing extension", log: log, type: .info)
                self?.completeRequest()
            } else {
                os_log("Text stash failed — cancelling extension", log: log, type: .error)
                self?.cancel()
            }
        }
    }

    private func stashFilePayload(_ url: URL) {
        os_log("Stashing file payload: %{public}@", log: log, type: .info, url.path)
        let body: [String: String] = [
            "type": "image",
            "file_path": url.path,
            "filename": url.lastPathComponent
        ]
        sendStashRequest(body) { [weak self] success in
            if success {
                os_log("File stash succeeded — completing extension", log: log, type: .info)
                self?.completeRequest()
            } else {
                os_log("File stash failed — cancelling extension", log: log, type: .error)
                self?.cancel()
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

    private func completeRequest() {
        os_log("Completing extension request — success", log: log, type: .info)
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    override func cancel() {
        os_log("Extension cancelled", log: log, type: .info)
        extensionContext?.cancelRequest(withError: NSError(
            domain: "ShareExtension",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "User canceled"]
        ))
        super.cancel()
    }
}
