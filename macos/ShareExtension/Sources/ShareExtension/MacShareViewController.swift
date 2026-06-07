import AppKit
import Social

private let socketPath = "Library/Application Support/au-search/qr-transfer.sock"

class MacShareViewController: SLComposeServiceViewController {

    override func viewDidAppear() {
        super.viewDidAppear()
        guard let context = extensionContext else {
            cancel()
            return
        }
        let items = context.inputItems as? [NSExtensionItem] ?? []
        processExtensionItems(items)
    }

    private func processExtensionItems(_ items: [NSExtensionItem]) {
        for item in items {
            guard let attachments = item.attachments else { continue }
            for provider in attachments {
                if provider.hasItemConformingToTypeIdentifier("public.plain-text") {
                    provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { [weak self] data, _ in
                        guard let text = data as? String else { return }
                        self?.stashTextPayload(text)
                    }
                    return
                }
                if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                    provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { [weak self] data, _ in
                        if let url = data as? URL {
                            self?.stashFilePayload(url)
                        } else if let path = data as? String {
                            self?.stashFilePayload(URL(fileURLWithPath: path))
                        }
                    }
                    return
                }
            }
        }
        cancel()
    }

    private func stashTextPayload(_ text: String) {
        let body: [String: String] = [
            "type": "text",
            "content": text
        ]
        sendStashRequest(body) { [weak self] success in
            if success {
                self?.completeRequest()
            } else {
                self?.cancel()
            }
        }
    }

    private func stashFilePayload(_ url: URL) {
        let body: [String: String] = [
            "type": "image",
            "file_path": url.path,
            "filename": url.lastPathComponent
        ]
        sendStashRequest(body) { [weak self] success in
            if success {
                self?.completeRequest()
            } else {
                self?.cancel()
            }
        }
    }

    private func sendStashRequest(_ body: [String: String], completion: @escaping (Bool) -> Void) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(false)
            return
        }

        guard let containerURL = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        ).first else {
            completion(false)
            return
        }

        let sockURL = containerURL.appendingPathComponent(socketPath)
        let sock = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sock >= 0 else {
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
        guard connectResult == 0 else { completion(false); return }

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
                if n <= 0 { break }
                sent += n
            }
        }

        var response = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = recv(sock, &buf, buf.count, 0)
            if n <= 0 { break }
            response.append(contentsOf: buf[..<n])
        }

        let responseStr = String(data: response, encoding: .utf8) ?? ""
        let success = responseStr.contains("201") || responseStr.contains("\"stashed\"")
        completion(success)
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }

    override func cancel() {
        extensionContext?.cancelRequest(withError: NSError(
            domain: "ShareExtension",
            code: 0,
            userInfo: [NSLocalizedDescriptionKey: "User canceled"]
        ))
        super.cancel()
    }
}
