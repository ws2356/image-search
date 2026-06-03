import Foundation

@available(iOS 15.0, *)
public struct InstantShareBootstrapResponse: Codable {
    public let accepted: Bool
    public let pcDeviceID: String

    enum CodingKeys: String, CodingKey {
        case accepted
        case pcDeviceID = "pc_device_id"
    }
}

@available(iOS 15.0, *)
public enum InstantShareBootstrapError: Error, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, message: String)
    case noData
    case pcDeviceIDMismatch(expected: String, got: String)
    case receiverBusy

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid bootstrap URL"
        case .httpError(let code, let msg):
            return "Bootstrap HTTP \(code): \(msg)"
        case .noData:
            return "Bootstrap returned no data"
        case .pcDeviceIDMismatch(let expected, let got):
            return "PC device ID mismatch: expected \(expected), got \(got)"
        case .receiverBusy:
            return "PC is busy with another session"
        }
    }
}

@available(iOS 15.0, *)
public final class InstantShareHTTPSessionBootstrapClient: NSObject, @unchecked Sendable {
    private var urlSession: URLSession!

    public override init() {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        self.urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    public func sendBootstrap(
        to host: String,
        port: Int,
        connectionConfig: InstantShareConnectionConfig,
        expectedPCDeviceID: String
    ) async throws {
        guard let url = URL(string: "http://\(host):\(port)/api/instant-share/v1/sessions/bootstrap") else {
            throw InstantShareBootstrapError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "session_id": connectionConfig.sessionID,
            "mobile_port": connectionConfig.mobilePort,
            "mobile_ip_list": connectionConfig.mobileIPList,
            "correlation_id": connectionConfig.correlationID,
            "payload_class": connectionConfig.metadata.payloadClass.rawValue,
            "target_intent": connectionConfig.metadata.targetIntent.rawValue,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        InstantShareLog.debug("[BootstrapClient] POST \(url.absoluteString)")
        InstantShareLog.debug("[BootstrapClient] body: \(String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "nil")")

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InstantShareBootstrapError.httpError(statusCode: 0, message: "Invalid response")
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            let errorCode: String
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let code = json["error_code"] as? String {
                errorCode = code
            } else {
                errorCode = "HTTP_\(httpResponse.statusCode)"
            }
            if errorCode == "RECEIVER_BUSY_SINGLE_SESSION" {
                throw InstantShareBootstrapError.receiverBusy
            }
            throw InstantShareBootstrapError.httpError(
                statusCode: httpResponse.statusCode,
                message: body
            )
        }

        guard !data.isEmpty else {
            throw InstantShareBootstrapError.noData
        }

        let decoder = JSONDecoder()
        let bootstrapResponse = try decoder.decode(InstantShareBootstrapResponse.self, from: data)

        guard bootstrapResponse.accepted else {
            throw InstantShareBootstrapError.httpError(
                statusCode: 200,
                message: "Bootstrap not accepted"
            )
        }

        guard bootstrapResponse.pcDeviceID == expectedPCDeviceID else {
            throw InstantShareBootstrapError.pcDeviceIDMismatch(
                expected: expectedPCDeviceID,
                got: bootstrapResponse.pcDeviceID
            )
        }

        InstantShareLog.debug("[BootstrapClient] bootstrap accepted by PC \(bootstrapResponse.pcDeviceID)")
    }
}

@available(iOS 15.0, *)
extension InstantShareHTTPSessionBootstrapClient: URLSessionDelegate {
    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        completionHandler(.performDefaultHandling, nil)
    }
}
