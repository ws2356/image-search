import AppKit
import Social
import os.log

private let socketPath = "Application Support/au-search/qr-transfer.sock"
private let log = OSLog(subsystem: "net.boldman.ausearch.share-extension", category: "ShareExtension")

class MacShareViewController: SLComposeServiceViewController {

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
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            os_log("Failed to serialize stash JSON", log: log, type: .error)
            completion(false)
            return
        }
        os_log("Sending stash request (%d bytes)", log: log, type: .info, jsonData.count)

        guard let containerURL = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else {
            os_log("Failed to resolve container URL", log: log, type: .error)
            completion(false)
            return
        }

        let sockURL = containerURL.appendingPathComponent(socketPath)
        os_log("Connecting to socket: %{public}@", log: log, type: .info, sockURL.path)

        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else {
            os_log("Failed to create Unix socket (errno=%d)", log: log, type: .error, errno)
            completion(false)
            return
        }
        defer { close(sock) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = sockURL.path
        let pathLen = min(path.utf8.count, MemoryLayout.size(ofValue: addr.sun_path) - 1)
        _ = path.withCString { src in
            withUnsafeMutablePointer(to: &addr.sun_path) { dst in
                dst.withMemoryRebound(to: CChar.self, capacity: pathLen) { ptr in
                    strncpy(ptr, src, pathLen)
                }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            os_log("Socket connect failed (errno=%d)", log: log, type: .error, errno)
            completion(false)
            return
        }
        os_log("Socket connected", log: log, type: .info)

        let request = """
        POST /api/instant-share/v1/qr-trigger HTTP/1.1\r
        Host: localhost\r
        Content-Type: application/json\r
        Content-Length: \(jsonData.count)\r
        Connection: close\r
        \r
        """ + String(data: jsonData, encoding: .utf8)!

        let requestData = Data(request.utf8)
        requestData.withUnsafeBytes { ptr in
            var sent = 0
            while sent < requestData.count {
                let n = send(sock, ptr.baseAddress! + sent, requestData.count - sent, 0)
                if n <= 0 {
                    os_log("Send failed after %d bytes (errno=%d)", log: log, type: .error, sent, errno)
                    break
                }
                sent += n
            }
        }
        os_log("Sent %d bytes to agent", log: log, type: .info, jsonData.count)

        var response = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = recv(sock, &buf, buf.count, 0)
            if n <= 0 { break }
            response.append(contentsOf: buf[..<n])
        }

        let responseStr = String(data: response, encoding: .utf8) ?? ""
        let success = responseStr.contains("201") || responseStr.contains("\"stashed\"")
        os_log("Stash response (%d bytes, success=%{bool}d): %{public}@",
               log: log, type: .info, response.count, success, String(responseStr.prefix(200)))
        completion(success)
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
