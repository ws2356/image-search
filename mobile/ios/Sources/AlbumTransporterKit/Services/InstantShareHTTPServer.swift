import CryptoKit
import Foundation
import Network
import Security
import UIKit

/// Manages the mobile-side HTTPS server for the instant-share protocol.
///
/// Loads the dev identity (P12 + PEM) from the app bundle, starts a TLS-enabled
/// NWListener on the configured port, and routes incoming PC requests to the
/// 6 protocol endpoints defined in `InstantShareProtocol`.
@MainActor
final class InstantShareHTTPServer: ObservableObject {
    enum ServerError: Error, LocalizedError {
        case identityLoadFailed
        case listenerStartFailed(String)
        case invalidPort

        var errorDescription: String? {
            switch self {
            case .identityLoadFailed:
                return "Failed to load instant-share identity (P12) from app bundle."
            case .listenerStartFailed(let detail):
                return "Failed to start TLS listener: \(detail)"
            case .invalidPort:
                return "Configured port is invalid."
            }
        }
    }

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var boundPort: UInt16? = nil
    @Published private(set) var lastError: String? = nil

    private let queue = DispatchQueue(label: "instant-share.http-server", qos: .userInitiated)
    private var listener: NWListener?
    private var identity: SecIdentity?
    private var publicKeyPEM: String?
    private var trustManager: InstantShareTrustSessionManager
    private var pinCode: String?
    private var pinConfirmationContinuation: CheckedContinuation<Bool, Never>?
    private var sharedText: String = ""
    private var sharedImageData: (bytes: Data, filename: String, contentType: String)?

    init(trustManager: InstantShareTrustSessionManager) {
        self.trustManager = trustManager
    }

    /// Load the P12 identity and PEM public key from the app bundle.
    func loadIdentity() throws {
        guard let p12URL = Bundle.module.url(
            forResource: "instant-share-dev-identity",
            withExtension: "p12.base64"
        ) else {
            throw ServerError.identityLoadFailed
        }
        let pemURL = Bundle.module.url(
            forResource: "instant-share-dev-public",
            withExtension: "pem"
        )
        let pem = pemURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        let p12Base64 = try String(contentsOf: p12URL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let p12Data = Data(base64Encoded: p12Base64) else {
            throw ServerError.identityLoadFailed
        }

        // Import P12 into keychain. The password is empty for the dev identity.
        let importPassword: String = ""
        let importOptions: [String: Any] = [
            kSecImportExportPassphrase as String: importPassword,
        ]
        var importedItems: CFArray?
        let importStatus = SecPKCS12Import(
            p12Data as CFData,
            importOptions as CFDictionary,
            &importedItems
        )
        guard importStatus == errSecSuccess,
              let items = importedItems as? [[String: Any]],
              let firstItem = items.first,
              let secIdentity = firstItem[kSecImportItemIdentity as String]
          else {
            throw ServerError.identityLoadFailed
        }

        self.identity = (secIdentity as! SecIdentity)
        self.publicKeyPEM = pem
    }

    /// Start listening for incoming PC connections.
    func start(port: UInt16) throws {
        guard !isRunning else { return }
        if identity == nil {
            try loadIdentity()
        }
        guard let identity else {
            throw ServerError.identityLoadFailed
        }
        guard (1...65535).contains(Int(port)) else {
            throw ServerError.invalidPort
        }

        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(
            tlsOptions.securityProtocolOptions,
            sec_identity_create(identity)!
        )
        sec_protocol_options_set_min_tls_protocol_version(
            tlsOptions.securityProtocolOptions,
            .TLSv13
        )

        let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw ServerError.invalidPort
        }
        let listener = try NWListener(using: parameters, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.handle(connection: connection)
            }
        }
        listener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isRunning = true
                    self?.boundPort = listener.port?.rawValue
                    self?.lastError = nil
                case .failed(let error):
                    self?.isRunning = false
                    self?.lastError = error.localizedDescription
                case .cancelled:
                    self?.isRunning = false
                    self?.boundPort = nil
                default:
                    break
                }
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    /// Stop the server.
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        boundPort = nil
    }

    /// Set the shared text payload to be served at /payload/text.
    func setSharedText(_ text: String) {
        self.sharedText = text
    }

    /// Set the shared image payload to be served at /payload/image.
    func setSharedImage(data: Data, filename: String, contentType: String) {
        self.sharedImageData = (data, filename, contentType)
    }

    /// Generate a new 6-digit PIN code and store it for the current session.
    @discardableResult
    func generatePIN() -> String {
        let pin = String(format: "%06d", Int.random(in: 0..<1_000_000))
        self.pinCode = pin
        return pin
    }

    /// Get the current PIN code (for UI display).
    var currentPIN: String? {
        pinCode
    }

    /// Verify the PIN sent by the PC during /trust/apply.
    func verifyPIN(_ providedPIN: String) -> Bool {
        guard let expected = pinCode else { return false }
        return providedPIN == expected
    }

    /// Long-poll for user confirmation of the trust relationship.
    /// The continuation is resumed when `confirmTrust()` is called from the UI.
    func awaitUserConfirmation(timeout: TimeInterval = 300) async -> Bool {
        let pinSnapshot = pinCode
        guard pinSnapshot != nil else { return false }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            self.pinConfirmationContinuation = continuation
        }
    }

    /// Called by the UI when the user taps "Confirm" on the PIN confirmation screen.
    func confirmTrust() {
        guard let continuation = pinConfirmationContinuation else { return }
        pinConfirmationContinuation = nil
        continuation.resume(returning: true)
    }

    /// Called by the UI when the user taps "Reject".
    func rejectTrust() {
        guard let continuation = pinConfirmationContinuation else { return }
        pinConfirmationContinuation = nil
        continuation.resume(returning: false)
    }

    var mobilePublicKeyPEM: String? {
        publicKeyPEM
    }

    // MARK: - Connection handling

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(connection: connection, accumulated: Data())
    }

    private func receiveRequest(connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = accumulated
            if let data, !data.isEmpty {
                buffer.append(data)
            }
            if let error {
                Task { @MainActor in
                    self.lastError = "Connection error: \(error.localizedDescription)"
                }
                connection.cancel()
                return
            }
            // Try to parse the request when we have a full header + body
            if let request = InstantShareHTTPRequest.parse(from: buffer) {
                Task { @MainActor in
                    await self.respond(to: request, on: connection)
                }
                return
            }
            if isComplete {
                connection.cancel()
                return
            }
            self.receiveRequest(connection: connection, accumulated: buffer)
        }
    }

    private func respond(to request: InstantShareHTTPRequest, on connection: NWConnection) async {
        let route = request.path
            .replacingOccurrences(of: InstantShareProtocol.apiPrefix, with: "")

        let response: InstantShareHTTPResponse
        switch route {
        case InstantShareProtocol.trustHandshakePath:
            response = await handleTrustHandshake(request: request)
        case InstantShareProtocol.trustApplyPath:
            response = await handleTrustApply(request: request)
        case InstantShareProtocol.trustConfirmPath:
            response = await handleTrustConfirm(request: request)
        case InstantShareProtocol.payloadTextPath:
            response = handlePayloadText()
        case InstantShareProtocol.payloadImagePath:
            response = handlePayloadImage()
        case InstantShareProtocol.deliveryResultPath:
            response = handleDeliveryResult(request: request)
        default:
            response = .notFound()
        }

        let raw = response.serialize()
        connection.send(content: raw, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Endpoint handlers

    private func handleTrustHandshake(request: InstantShareHTTPRequest) async -> InstantShareHTTPResponse {
        guard let body = request.jsonBody,
              let pcDHPublicKey = body["pc_dh_public_key"] as? String,
              let pcNonce = body["pc_nonce"] as? String else {
            return .badRequest(errorCode: "INVALID_REQUEST", message: "Missing pc_dh_public_key or pc_nonce")
        }
        do {
            let handshakeResponse = try trustManager.handleHandshakeRequest(
                pcDHPublicKey: pcDHPublicKey,
                pcNonce: pcNonce
            )
            let responseDict: [String: Any] = [
                "mobile_dh_public_key": handshakeResponse.mobileDHPublicKey,
                "mobile_nonce": handshakeResponse.mobileNonce,
                "kdf_context": handshakeResponse.kdfContext,
            ]
            return .json(status: 200, body: responseDict)
        } catch {
            return .badRequest(errorCode: "HANDSHAKE_REQUIRED", message: error.localizedDescription)
        }
    }

    private func handleTrustApply(request: InstantShareHTTPRequest) async -> InstantShareHTTPResponse {
        guard let body = request.jsonBody else {
            return .badRequest(errorCode: "INVALID_REQUEST", message: "Missing body")
        }
        do {
            let envelope = InstantShareTrustEnvelope(
                schema: body["schema"] as? String ?? "",
                nonce: body["nonce"] as? String ?? "",
                ciphertext: body["ciphertext"] as? String ?? ""
            )
            let decrypted = try trustManager.decryptEnvelope(envelope)
            guard let pinCode = decrypted["pin_code"] as? String else {
                return .badRequest(errorCode: "INVALID_REQUEST", message: "Missing pin_code in trust envelope")
            }
            let isValid = verifyPIN(pinCode)
            if isValid {
                return .json(status: 202, body: ["apply_status": "accepted"])
            } else {
                return .json(
                    status: 409,
                    body: [
                        "error_code": "PIN_MISMATCH_OR_REJECTED",
                        "message": "PIN code does not match.",
                        "retryable": false,
                    ]
                )
            }
        } catch {
            return .badRequest(errorCode: "PAYLOAD_UNREADABLE", message: error.localizedDescription)
        }
    }

    private func handleTrustConfirm(request: InstantShareHTTPRequest) async -> InstantShareHTTPResponse {
        let confirmed = await awaitUserConfirmation()
        if !confirmed {
            return .json(
                status: 409,
                body: [
                    "error_code": "PIN_MISMATCH_OR_REJECTED",
                    "message": "User rejected the trust confirmation.",
                    "retryable": false,
                ]
            )
        }
        do {
            let responsePayload: [String: Any] = [
                "mobile_public_key_pem": publicKeyPEM ?? "",
                "trust_status": "trusted",
            ]
            let envelope = try trustManager.encryptResponse(responsePayload)
            let envelopeDict: [String: Any] = [
                "schema": envelope.schema,
                "nonce": envelope.nonce,
                "ciphertext": envelope.ciphertext,
            ]
            return .json(status: 200, body: envelopeDict)
        } catch {
            return .badRequest(errorCode: "PAYLOAD_UNREADABLE", message: error.localizedDescription)
        }
    }

    private func handlePayloadText() -> InstantShareHTTPResponse {
        let body: [String: Any] = [
            "state": "delivering",
            "text_utf8": sharedText,
        ]
        return .json(status: 200, body: body)
    }

    private func handlePayloadImage() -> InstantShareHTTPResponse {
        guard let imageData = sharedImageData else {
            return .badRequest(errorCode: "PAYLOAD_UNREADABLE", message: "No image payload configured.")
        }
        var headers: [String: String] = [
            "Content-Type": imageData.contentType,
            "X-Instant-Share-Filename": imageData.filename,
        ]
        return .raw(status: 200, body: imageData.bytes, headers: headers)
    }

    private func handleDeliveryResult(request: InstantShareHTTPRequest) -> InstantShareHTTPResponse {
        return .json(status: 200, body: ["ack": true])
    }
}

// MARK: - HTTP request/response parsing

struct InstantShareHTTPRequest {
    let method: String
    let path: String
    var headers: [String: String]
    let body: Data

    var jsonBody: [String: Any]? {
        guard !body.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    static func parse(from data: Data) -> InstantShareHTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data.subdata(in: 0..<headerEnd.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        let method = parts[0]
        let path = parts[1]
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[..<colonIndex].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        let contentLength = Int(headers["Content-Length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        let bodyAvailable = data.count - bodyStart
        guard bodyAvailable >= contentLength else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        return InstantShareHTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}

struct InstantShareHTTPResponse {
    let status: Int
    var headers: [String: String]
    let body: Data

    static func json(status: Int, body: [String: Any]) -> InstantShareHTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
        return InstantShareHTTPResponse(
            status: status,
            headers: ["Content-Type": "application/json"],
            body: data
        )
    }

    static func raw(status: Int, body: Data, headers: [String: String]) -> InstantShareHTTPResponse {
        var mergedHeaders = headers
        mergedHeaders["Content-Length"] = String(body.count)
        return InstantShareHTTPResponse(status: status, headers: mergedHeaders, body: body)
    }

    static func badRequest(errorCode: String, message: String) -> InstantShareHTTPResponse {
        return .json(
            status: 400,
            body: [
                "error_code": errorCode,
                "message": message,
                "retryable": false,
            ]
        )
    }

    static func notFound() -> InstantShareHTTPResponse {
        return .json(
            status: 404,
            body: [
                "error_code": "INVALID_REQUEST",
                "message": "Unknown route",
                "retryable": false,
            ]
        )
    }

    func serialize() -> Data {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 202: statusText = "Accepted"
        case 400: statusText = "Bad Request"
        case 404: statusText = "Not Found"
        case 409: statusText = "Conflict"
        case 500: statusText = "Internal Server Error"
        default: statusText = "Status \(status)"
        }
        var response = "HTTP/1.1 \(status) \(statusText)\r\n"
        var mergedHeaders = headers
        if mergedHeaders["Content-Length"] == nil {
            mergedHeaders["Content-Length"] = String(body.count)
        }
        if mergedHeaders["Connection"] == nil {
            mergedHeaders["Connection"] = "close"
        }
        for (key, value) in mergedHeaders.sorted(by: { $0.key < $1.key }) {
            response += "\(key): \(value)\r\n"
        }
        response += "\r\n"
        var data = response.data(using: .utf8) ?? Data()
        data.append(body)
        return data
    }
}
