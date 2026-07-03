import CryptoKit
import Foundation
#if canImport(UIKit)
import UIKit
#endif
import Common

enum InstantShareTrustClientError: Error, Sendable {
    case handshakeFailed(String)
    case applyFailed(String)
    case confirmFailed(String)
    case sessionKeyNotEstablished
    case invalidResponse(String)
    case httpError(statusCode: Int, errorCode: String, message: String)
    case networkError(Error)
}

extension InstantShareTrustClientError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .handshakeFailed(let message):
            return "Trust handshake failed: \(message)"
        case .applyFailed(let message):
            return "Trust apply (PIN retrieval) failed: \(message)"
        case .confirmFailed(let message):
            return "Trust confirm failed: \(message)"
        case .sessionKeyNotEstablished:
            return "Session key not established. Complete handshake first."
        case .invalidResponse(let message):
            return "Invalid response from PC: \(message)"
        case .httpError(let statusCode, let errorCode, let message):
            return "HTTP \(statusCode): [\(errorCode)] \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

final class InstantShareTrustClient: @unchecked Sendable {
    private let trustSessionManager: InstantShareTrustSessionManager
    private let urlSession: URLSession
    private let timeoutInterval: TimeInterval

    init(
        trustSessionManager: InstantShareTrustSessionManager,
        urlSession: URLSession = .shared,
        timeoutInterval: TimeInterval = 2.0
    ) {
        self.trustSessionManager = trustSessionManager
        self.urlSession = urlSession
        self.timeoutInterval = timeoutInterval
    }

    func handshake(
        hosts: [String],
        port: Int,
        sessionID: String,
        correlationID: String,
        mobilePort: Int = 1,
        mobileIPList: [String] = ["127.0.0.1"],
        payloadClass: String = "text",
        targetIntent: String = "clipboard_only",
        trustMode: String = "first_share"
    ) async throws -> InstantShareTrustHandshakeResponse {
        return try await withHostFallback(hosts: hosts) { host in
            try await self.handshakeSingleHost(
                host: host, port: port, sessionID: sessionID, correlationID: correlationID,
                mobilePort: mobilePort, mobileIPList: mobileIPList, payloadClass: payloadClass,
                targetIntent: targetIntent, trustMode: trustMode
            )
        }
    }

    private func handshakeSingleHost(
        host: String,
        port: Int,
        sessionID: String,
        correlationID: String,
        mobilePort: Int,
        mobileIPList: [String],
        payloadClass: String,
        targetIntent: String,
        trustMode: String
    ) async throws -> InstantShareTrustHandshakeResponse {
        let mobileDHPublicKey = trustSessionManager.publicKeyBase64URL
        let mobileNonce = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
            .instantShareBase64URLEncodedString()

        var requestBody: [String: Any] = [
            "mobile_dh_public_key": mobileDHPublicKey,
            "mobile_nonce": mobileNonce,
            "mobile_port": mobilePort,
            "mobile_ip_list": mobileIPList,
            "payload_class": payloadClass,
            "target_intent": targetIntent,
            "trust_mode": trustMode,
        ]

        let urlString = "http://\(host):\(port)\(InstantShareProtocol.apiPrefix)/trust/handshake"
        guard let url = URL(string: urlString) else {
            throw InstantShareTrustClientError.handshakeFailed("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionID, forHTTPHeaderField: "X-Session-Id")
        request.setValue(correlationID, forHTTPHeaderField: "X-Correlation-Id")
        request.timeoutInterval = timeoutInterval

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw InstantShareTrustClientError.handshakeFailed("Failed to encode request body: \(error)")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw InstantShareTrustClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InstantShareTrustClientError.handshakeFailed("Non-HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorInfo = tryParseErrorBody(data)
            throw InstantShareTrustClientError.httpError(
                statusCode: httpResponse.statusCode,
                errorCode: errorInfo.errorCode,
                message: errorInfo.message
            )
        }

        let responseBody: [String: Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw InstantShareTrustClientError.invalidResponse("Response is not a JSON object")
            }
            responseBody = decoded
        } catch let error as InstantShareTrustClientError {
            throw error
        } catch {
            throw InstantShareTrustClientError.invalidResponse("Failed to decode response: \(error)")
        }

        guard let pcDHPublicKey = responseBody["pc_dh_public_key"] as? String,
              let pcNonce = responseBody["pc_nonce"] as? String,
              let kdfContext = responseBody["kdf_context"] as? String else {
            throw InstantShareTrustClientError.invalidResponse("Missing pc_dh_public_key, pc_nonce, or kdf_context in handshake response")
        }

        let handshakeResponse = try trustSessionManager.handleHandshakeRequest(
            pcDHPublicKey: pcDHPublicKey,
            pcNonce: pcNonce,
            pcKdfContext: kdfContext,
            mobileNonce: mobileNonce
        )

        return handshakeResponse
    }

    func apply(
        hosts: [String],
        port: Int,
        sessionID: String,
        correlationID: String
    ) async throws {
        try await withHostFallback(hosts: hosts) { host in
            try await self.applySingleHost(host: host, port: port, sessionID: sessionID, correlationID: correlationID)
        }
    }

    private func applySingleHost(
        host: String,
        port: Int,
        sessionID: String,
        correlationID: String
    ) async throws {
        guard trustSessionManager.isEstablished else {
            throw InstantShareTrustClientError.sessionKeyNotEstablished
        }

        let requestPayload: [String: Any] = [
            "action": "request_pin",
            "peer_device_name": await Self.currentDeviceName(),
        ]
        let envelope = try trustSessionManager.encryptResponse(requestPayload)

        let requestBody: [String: Any] = [
            "schema": envelope.schema,
            "nonce": envelope.nonce,
            "ciphertext": envelope.ciphertext,
            "encryption_alg": "aes-256-gcm",
        ]

        let urlString = "http://\(host):\(port)\(InstantShareProtocol.apiPrefix)/trust/apply"
        guard let url = URL(string: urlString) else {
            throw InstantShareTrustClientError.applyFailed("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionID, forHTTPHeaderField: "X-Session-Id")
        request.setValue(correlationID, forHTTPHeaderField: "X-Correlation-Id")
        request.timeoutInterval = timeoutInterval

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw InstantShareTrustClientError.applyFailed("Failed to encode request body: \(error)")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw InstantShareTrustClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InstantShareTrustClientError.applyFailed("Non-HTTP response")
        }

        guard httpResponse.statusCode == 202 else {
            let errorInfo = tryParseErrorBody(data)
            throw InstantShareTrustClientError.httpError(
                statusCode: httpResponse.statusCode,
                errorCode: errorInfo.errorCode,
                message: errorInfo.message
            )
        }
    }

    func confirm(
        hosts: [String],
        port: Int,
        sessionID: String,
        correlationID: String,
        pinCode: String,
        deviceCertificatePEM: String? = nil
    ) async throws -> String? {
        return try await withHostFallback(hosts: hosts) { host in
            try await self.confirmSingleHost(
                host: host, port: port, sessionID: sessionID, correlationID: correlationID,
                pinCode: pinCode, deviceCertificatePEM: deviceCertificatePEM
            )
        }
    }

    private func confirmSingleHost(
        host: String,
        port: Int,
        sessionID: String,
        correlationID: String,
        pinCode: String,
        deviceCertificatePEM: String?
    ) async throws -> String? {
        guard trustSessionManager.isEstablished else {
            throw InstantShareTrustClientError.sessionKeyNotEstablished
        }

        var requestPayload: [String: Any] = ["action": "confirm", "pin_code": pinCode]
        if let cert = deviceCertificatePEM {
            requestPayload["device_certificate_pem"] = cert
        }
        let envelope = try trustSessionManager.encryptResponse(requestPayload)

        let requestBody: [String: Any] = [
            "schema": envelope.schema,
            "nonce": envelope.nonce,
            "ciphertext": envelope.ciphertext,
            "encryption_alg": "aes-256-gcm",
        ]

        let urlString = "http://\(host):\(port)\(InstantShareProtocol.apiPrefix)/trust/confirm"
        guard let url = URL(string: urlString) else {
            throw InstantShareTrustClientError.confirmFailed("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionID, forHTTPHeaderField: "X-Session-Id")
        request.setValue(correlationID, forHTTPHeaderField: "X-Correlation-Id")
        request.timeoutInterval = timeoutInterval

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw InstantShareTrustClientError.confirmFailed("Failed to encode request body: \(error)")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw InstantShareTrustClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InstantShareTrustClientError.confirmFailed("Non-HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorInfo = tryParseErrorBody(data)
            throw InstantShareTrustClientError.httpError(
                statusCode: httpResponse.statusCode,
                errorCode: errorInfo.errorCode,
                message: errorInfo.message
            )
        }

        let responseBody: [String: Any]
        do {
            guard let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw InstantShareTrustClientError.invalidResponse("Response is not a JSON object")
            }
            responseBody = decoded
        } catch let error as InstantShareTrustClientError {
            throw error
        } catch {
            throw InstantShareTrustClientError.invalidResponse("Failed to decode response: \(error)")
        }

        let responseEnvelope = InstantShareTrustEnvelope(
            nonce: responseBody["nonce"] as? String ?? "",
            ciphertext: responseBody["ciphertext"] as? String ?? ""
        )

        let decryptedPayload = try trustSessionManager.decryptEnvelope(responseEnvelope)
        guard let trustStatus = decryptedPayload["trust_status"] as? String,
              trustStatus == "trusted" else {
            throw InstantShareTrustClientError.confirmFailed("Expected trust_status=trusted, got \(decryptedPayload)")
        }
        let pcCertificatePEM = decryptedPayload["device_certificate_pem"] as? String
        return pcCertificatePEM
    }

    /// Try `operation` with the first host; on network error, fall back to subsequent hosts.
    /// Non-network errors (HTTP errors, protocol errors) are thrown immediately.
    private func withHostFallback<T>(
        hosts: [String],
        operation: @escaping (String) async throws -> T
    ) async throws -> T {
        guard let firstHost = hosts.first else {
            throw InstantShareTrustClientError.networkError(
                URLError(.cannotFindHost)
            )
        }
        var lastError: Error?
        for host in hosts {
            do {
                return try await operation(host)
            } catch let error as InstantShareTrustClientError {
                switch error {
                case .networkError:
                    lastError = error
                    LocalLog.debug("[TrustClient] host \(host) failed with network error, trying next")
                    continue
                default:
                    throw error
                }
            }
        }
        throw lastError ?? InstantShareTrustClientError.networkError(URLError(.cannotFindHost))
    }

    private static func currentDeviceName() -> String {
        #if canImport(UIKit)
        UIDevice.current.name
        #else
        ProcessInfo.processInfo.hostName
        #endif
    }

    private func tryParseErrorBody(_ data: Data) -> (errorCode: String, message: String) {
        guard let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (errorCode: "UNKNOWN", message: "Unable to parse error response")
        }
        return (
            errorCode: decoded["error_code"] as? String ?? "UNKNOWN",
            message: decoded["message"] as? String ?? "Unknown error"
        )
    }
}
