import AsyncHTTPClient
import Foundation
import NIOCore
import NIOHTTP1

/// HTTP client that talks to a local daemon over a Unix domain socket using
/// `swift-server/async-http-client`. The package supports UDS as a first-class
/// transport via `HTTPClient.execute(_:socketPath:urlPath:...)`, so no custom
/// transport wiring (URLProtocol, raw sockets, etc.) is needed.
///
/// HTTP/1.1 is forced because the Launch Agent speaks plain HTTP/1.1 over the
/// socket — there is no TLS handshake, and HTTP/2 negotiation would just add
/// latency and surface incompatibilities.
final class UDSHTTPClient {
    let httpClient: HTTPClient
    let socketPath: String

    init(socketPath: String) {
        self.socketPath = socketPath
        var configuration = HTTPClient.Configuration()
        configuration.httpVersion = .http1Only
        configuration.timeout = HTTPClient.Configuration.Timeout(
            connect: .seconds(5),
            read: .seconds(10)
        )
        self.httpClient = HTTPClient(
            eventLoopGroupProvider: .singleton,
            configuration: configuration
        )
    }

    deinit {
        try? httpClient.syncShutdown()
    }

    /// Send a JSON POST over the configured UDS. Completion is delivered on the
    /// main queue so callers can drive UI (`completeRequest` / `cancel`) directly.
    func postJSON(
        path: String,
        body: [String: Any],
        completion: @escaping (Result<(Data, Int), Error>) -> Void
    ) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            DispatchQueue.main.async {
                completion(.failure(Self.error(code: -1, message: "Failed to serialize JSON body")))
            }
            return
        }

        guard let url = URL(httpURLWithSocketPath: socketPath, uri: path) else {
            DispatchQueue.main.async {
                completion(.failure(Self.error(code: -2, message: "Failed to construct UDS URL for path: \(path)")))
            }
            return
        }

        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Host", value: "localhost")

        let request: HTTPClient.Request
        do {
            request = try HTTPClient.Request(
                url: url,
                method: .POST,
                headers: headers,
                body: .bytes(jsonData)
            )
        } catch {
            DispatchQueue.main.async { completion(.failure(error)) }
            return
        }

        let future = httpClient.execute(request: request)
        future.whenComplete { result in
            let resolved: Result<(Data, Int), Error>
            switch result {
            case .failure(let error):
                resolved = .failure(error)
            case .success(let response):
                let data = response.body.map { Data(buffer: $0) } ?? Data()
                resolved = .success((data, Int(response.status.code)))
            }
            DispatchQueue.main.async { completion(resolved) }
        }
    }

    private static func error(code: Int, message: String) -> NSError {
        NSError(domain: "UDSHTTPClient", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
