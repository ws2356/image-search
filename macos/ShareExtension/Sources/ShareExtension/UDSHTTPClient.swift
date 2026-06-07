import Foundation
import Network

private let kUDSURLScheme = "http"
private let kUDSURLHost = "localhost"

/// High-level HTTP client that talks to a local daemon over a Unix domain socket
/// while exposing the standard `URLSession` API surface.
///
/// `NSURLSession` does not support UDS transport natively, so this client registers
/// a custom `URLProtocol` (`UDSURLProtocol`) on the session. The protocol intercepts
/// `http://localhost/...` requests, opens an `NWConnection` to the configured UDS
/// path, serializes the request to HTTP/1.1 bytes, and parses the response back
/// into an `HTTPURLResponse`. Callers get the standard `URLSession.dataTask`
/// completion API.
///
/// `connectionProxyDictionary` is set to an empty dictionary to ensure that
/// `http://localhost` traffic is never diverted through a system HTTP proxy.
final class UDSHTTPClient {
    let session: URLSession
    let socketPath: String

    init(socketPath: String) {
        self.socketPath = socketPath
        UDSURLProtocol.sharedSocketPath = socketPath

        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.protocolClasses = [UDSURLProtocol.self]
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData

        self.session = URLSession(configuration: config)
    }

    deinit {
        session.invalidateAndCancel()
    }

    /// Send a JSON POST to `http://localhost<path>`. The completion is delivered on
    /// the main queue so callers can drive UI (`completeRequest` / `cancel`) directly.
    func postJSON(
        path: String,
        body: [String: String],
        completion: @escaping (Result<(Data, HTTPURLResponse), Error>) -> Void
    ) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            DispatchQueue.main.async {
                completion(.failure(Self.error(code: -1, message: "Failed to serialize JSON body")))
            }
            return
        }

        guard let url = URL(string: "\(kUDSURLScheme)://\(kUDSURLHost)\(path)") else {
            DispatchQueue.main.async {
                completion(.failure(Self.error(code: -2, message: "Invalid URL path: \(path)")))
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let task = session.dataTask(with: request) { data, response, error in
            let result: Result<(Data, HTTPURLResponse), Error>
            if let error = error {
                result = .failure(error)
            } else if let data = data, let httpResponse = response as? HTTPURLResponse {
                result = .success((data, httpResponse))
            } else {
                result = .failure(Self.error(code: -3, message: "Invalid response (no data or response)"))
            }
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
    }

    private static func error(code: Int, message: String) -> NSError {
        NSError(domain: "UDSHTTPClient", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// `URLProtocol` that proxies `http://localhost/...` requests to a Unix domain
/// socket via `NWConnection`. The protocol owns the connection lifecycle for the
/// duration of a single request/response exchange and is registered on the
/// `URLSession` instances created by `UDSHTTPClient`.
final class UDSURLProtocol: URLProtocol {
    /// Single socket path shared by all `UDSHTTPClient` instances in this process.
    /// The share extension only ever talks to one local daemon, so a process-wide
    /// setting is sufficient and keeps the protocol API URL-only.
    static var sharedSocketPath: String?

    private static let workQueue = DispatchQueue(
        label: "net.boldman.ausearch.share-extension.uds",
        qos: .userInitiated
    )

    private var connection: NWConnection?
    private var responseBuffer = Data()
    private var headerEndOffset: Int?
    private var expectedBodyLength: Int?
    private var hasFinished = false

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        return url.scheme == kUDSURLScheme && url.host == kUDSURLHost
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let socketPath = UDSURLProtocol.sharedSocketPath, !socketPath.isEmpty else {
            fail(NSError(domain: "UDSURLProtocol", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Socket path not configured"
            ]))
            return
        }

        let connection = NWConnection(to: .unix(path: socketPath), using: .tcp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.sendRequest()
            case .failed(let error):
                self.fail(error)
            case .waiting(let error):
                self.fail(error)
            case .cancelled:
                break
            default:
                break
            }
        }

        connection.start(queue: UDSURLProtocol.workQueue)
    }

    override func stopLoading() {
        connection?.cancel()
        connection = nil
    }

    // MARK: - Request

    private func sendRequest() {
        guard let url = self.request.url,
              let connection = self.connection else { return }
        let request = self.request

        let method = request.httpMethod ?? "GET"
        let path = url.path.isEmpty ? "/" : url.path
        let query = url.query.map { "?\($0)" } ?? ""

        var headerLines: [String] = [
            "\(method) \(path)\(query) HTTP/1.1",
            "Host: \(url.host ?? kUDSURLHost)"
        ]
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            headerLines.append("\(key): \(value)")
        }
        if let body = request.httpBody,
           request.value(forHTTPHeaderField: "Content-Length") == nil {
            headerLines.append("Content-Length: \(body.count)")
        }
        headerLines.append("Connection: close")

        var bytes = Data((headerLines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        if let body = request.httpBody {
            bytes.append(body)
        }

        connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.fail(error)
                return
            }
            self.receiveLoop()
        })
    }

    // MARK: - Response

    private func receiveLoop() {
        guard let connection = self.connection else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                self.fail(error)
                return
            }
            if let data = data, !data.isEmpty {
                self.responseBuffer.append(data)
            }
            self.parseResponseHeadersIfNeeded()
            if self.hasCompleteBody() {
                self.deliverResponse(headerEnd: self.headerEndOffset!)
                return
            }
            if isComplete {
                if let headerEnd = self.headerEndOffset {
                    self.deliverResponse(headerEnd: headerEnd)
                } else {
                    self.fail(NSError(domain: "UDSURLProtocol", code: -5, userInfo: [
                        NSLocalizedDescriptionKey: "Connection closed before headers received"
                    ]))
                }
                return
            }
            self.receiveLoop()
        }
    }

    private func parseResponseHeadersIfNeeded() {
        guard headerEndOffset == nil else { return }
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])  // \r\n\r\n
        guard let range = responseBuffer.range(of: separator) else { return }
        headerEndOffset = range.upperBound
        expectedBodyLength = parseContentLength(in: responseBuffer.subdata(in: 0..<range.upperBound))
    }

    private func parseContentLength(in headerData: Data) -> Int? {
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        for line in headerText.components(separatedBy: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            if key == "content-length" {
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if let length = Int(value) { return length }
            }
        }
        return nil
    }

    private func hasCompleteBody() -> Bool {
        guard let headerEnd = headerEndOffset else { return false }
        guard let expected = expectedBodyLength else { return false }
        return responseBuffer.count - headerEnd >= expected
    }

    private func deliverResponse(headerEnd: Int) {
        guard !hasFinished, let url = self.request.url else { return }
        hasFinished = true

        let headerData = responseBuffer.subdata(in: 0..<headerEnd)
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "UDSURLProtocol", code: -2, userInfo: [
                NSLocalizedDescriptionKey: "Invalid response encoding"
            ]))
            connection?.cancel()
            return
        }

        let lines = headerText.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "UDSURLProtocol", code: -3, userInfo: [
                NSLocalizedDescriptionKey: "Missing status line"
            ]))
            connection?.cancel()
            return
        }

        let statusParts = statusLine.split(separator: " ", maxSplits: 2)
        let statusCode = statusParts.count >= 2 ? (Int(statusParts[1]) ?? 0) : 0

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty {
                headers[key] = value
            }
        }

        let bodyData = responseBuffer.subdata(in: headerEnd..<responseBuffer.count)

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "UDSURLProtocol", code: -4, userInfo: [
                NSLocalizedDescriptionKey: "Failed to construct HTTPURLResponse"
            ]))
            connection?.cancel()
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bodyData)
        client?.urlProtocolDidFinishLoading(self)
        connection?.cancel()
    }

    private func fail(_ error: Error) {
        guard !hasFinished else { return }
        hasFinished = true
        client?.urlProtocol(self, didFailWithError: error)
        connection?.cancel()
    }
}
