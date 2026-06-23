import Common
import CryptoKit
import Foundation
import UIKit

// MARK: - Internal Trust Session Manager (pc-to-mobile flow)

private enum ISPCProtocol {
    static let apiPrefix = "/api/instant-share/v1"
    static let trustHandshakePath = "/trust/handshake"
    static let trustConfirmPath = "/trust/confirm"
    static let transferManifestPath = "/transfer/manifest"
    static let trustEnvelopeSchema = "dtis.instant-share.trust-envelope.v1"
    static let trustEnvelopeNonceBytes = 12
}

private enum ISPCServiceError: Error {
    case invalidTrustEnvelope
    case invalidTrustEnvelopeField(String)
    case invalidPlaintextJSONObject
    case decryptionFailed
}

private struct ISPCTrustEnvelope {
    var schema = ISPCProtocol.trustEnvelopeSchema
    var nonce: String
    var ciphertext: String
}

private final class ISPCTrustSessionManager: @unchecked Sendable {
    private let lock = NSLock()
    private var privateKey: Curve25519.KeyAgreement.PrivateKey
    private(set) var publicKeyBase64URL: String
    private var sessionKey: SymmetricKey?

    init() {
        let ephemeralKey = Curve25519.KeyAgreement.PrivateKey()
        self.privateKey = ephemeralKey
        self.publicKeyBase64URL = ephemeralKey.publicKey.rawRepresentation.ispcBase64URLEncodedString()
    }

    func handleHandshakeRequest(
        pcDHPublicKey: String,
        pcNonce: String,
        pcKdfContext: String,
        mobileNonce: String
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        let pcPublicKeyData = try Data(ispcBase64URLEncoded: pcDHPublicKey)
        guard pcPublicKeyData.count == 32 else {
            throw ISPCServiceError.invalidTrustEnvelopeField("pc_dh_public_key")
        }
        let pcNonceData = try Data(ispcBase64URLEncoded: pcNonce)
        guard pcNonceData.count == 32 else {
            throw ISPCServiceError.invalidTrustEnvelopeField("pc_nonce")
        }
        let kdfContextData = try Data(ispcBase64URLEncoded: pcKdfContext)
        let mobileNonceData = try Data(ispcBase64URLEncoded: mobileNonce)

        let pcPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: pcPublicKeyData)
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: pcPublicKey)

        let derivedKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: pcNonceData + mobileNonceData,
            sharedInfo: Data("dtis.instant-share.trust-session.v1".utf8) + kdfContextData,
            outputByteCount: 32
        )
        self.sessionKey = derivedKey
    }

    var isEstablished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sessionKey != nil
    }

    func encryptPayload(_ payload: [String: Any]) throws -> ISPCTrustEnvelope {
        lock.lock()
        defer { lock.unlock() }

        guard let sessionKey else {
            throw ISPCServiceError.invalidTrustEnvelope
        }
        guard JSONSerialization.isValidJSONObject(payload) else {
            throw ISPCServiceError.invalidPlaintextJSONObject
        }
        let nonce = AES.GCM.Nonce()
        let plaintext = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let sealedBox = try AES.GCM.seal(plaintext, using: sessionKey, nonce: nonce)
        guard let combinedCiphertext = sealedBox.combined else {
            throw ISPCServiceError.invalidTrustEnvelope
        }
        let nonceData = Data(nonce)
        let ciphertextData = combinedCiphertext.dropFirst(nonceData.count)
        return ISPCTrustEnvelope(
            nonce: nonceData.ispcBase64URLEncodedString(),
            ciphertext: ciphertextData.ispcBase64URLEncodedString()
        )
    }

    func decryptEnvelope(_ envelope: ISPCTrustEnvelope) throws -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }

        guard let sessionKey else {
            throw ISPCServiceError.decryptionFailed
        }
        guard envelope.schema == ISPCProtocol.trustEnvelopeSchema else {
            throw ISPCServiceError.invalidTrustEnvelope
        }
        let nonceData = try Data(ispcBase64URLEncoded: envelope.nonce)
        guard nonceData.count == ISPCProtocol.trustEnvelopeNonceBytes else {
            throw ISPCServiceError.invalidTrustEnvelopeField("nonce")
        }
        let ciphertextData = try Data(ispcBase64URLEncoded: envelope.ciphertext)
        let combined = nonceData + ciphertextData
        let sealedBox = try AES.GCM.SealedBox(combined: combined)
        let plaintext = try AES.GCM.open(sealedBox, using: sessionKey)
        let decodedPayload = try JSONSerialization.jsonObject(with: plaintext)
        guard let payload = decodedPayload as? [String: Any] else {
            throw ISPCServiceError.invalidTrustEnvelope
        }
        return payload
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        let ephemeralKey = Curve25519.KeyAgreement.PrivateKey()
        privateKey = ephemeralKey
        publicKeyBase64URL = ephemeralKey.publicKey.rawRepresentation.ispcBase64URLEncodedString()
        sessionKey = nil
    }
}

private extension Data {
    func ispcBase64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init(ispcBase64URLEncoded value: String) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ISPCServiceError.invalidTrustEnvelope
        }
        let base64 = normalized
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let decoded = Data(base64Encoded: base64 + padding) else {
            throw ISPCServiceError.invalidTrustEnvelope
        }
        self = decoded
    }
}

// MARK: - Public API

public enum QRTriggerDownloadClientError: Error, Sendable {
    case invalidURL
    case networkError(Error)
    case httpError(statusCode: Int, message: String)
    case invalidOptCode
    case stashExpired
    case stashNotFound
    case serverError(String)
    case allHostsFailed([Error])
    case invalidResponse
    case handshakeFailed(String)
    case confirmFailed(String)
    case downloadFailed(String)
    case tlsVerificationFailed(String)
}

extension QRTriggerDownloadClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let statusCode, let message):
            return "HTTP \(statusCode): \(message)"
        case .invalidOptCode:
            return "Invalid code. Make sure the code on your Mac screen is correct."
        case .stashExpired:
            return "This share has expired. Please share the data again from your Mac."
        case .stashNotFound:
            return "Share not found. It may have been cancelled."
        case .serverError(let message):
            return "Something went wrong. Please try again. (\(message))"
        case .allHostsFailed:
            return "Could not connect to your Mac. Make sure both devices are on the same Wi-Fi network."
        case .invalidResponse:
            return "Invalid response from server"
        case .handshakeFailed(let message):
            return "Trust handshake failed: \(message)"
        case .confirmFailed(let message):
            return "Trust confirm failed: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .tlsVerificationFailed(let message):
            return "TLS verification failed: \(message)"
        }
    }
}

public struct MultiFileManifest: Sendable {
    public let fileCount: Int
    public let files: [FileEntry]

    public struct FileEntry: Sendable, Identifiable {
        public let index: Int
        public let type: String  // "text", "html", or "file"
        public let filename: String
        public let contentType: String
        public let sizeBytes: Int
        public let content: String?  // inline content for text/html entries

        public var id: Int { index }

        public var isInline: Bool { type == "text" || type == "html" }
        public var isFileDownload: Bool { type == "file" }
    }
}

public enum QRClaimResult: Sendable {
    case text(String)
    case html(String)
    case image(fileURL: URL, contentType: String, filename: String?)
    case file(fileURL: URL, contentType: String, filename: String?)
    case multiFile(manifest: MultiFileManifest, host: String, tlsPort: Int, sessionId: String, correlationID: String)
}

extension QRClaimResult {
    var fileUrls: [URL] {
        switch self {
        case .file(let fileURL, _, _):
            return [fileURL]
        case .image(let fileURL, _, _):
            return [fileURL]
        case .multiFile:
            return []
        default:
            return []
        }
    }
}

public final class QRTriggerDownloadClient: Sendable {
    private let urlSession: URLSession
    private let timeoutInterval: TimeInterval
    private let appIdentityProvider: AppIdentityProviding
    private let trustSessionManager = ISPCTrustSessionManager()

    public init(
        urlSession: URLSession = .shared,
        timeoutInterval: TimeInterval = 30.0,
        appIdentityProvider: AppIdentityProviding
    ) {
        self.urlSession = urlSession
        self.timeoutInterval = timeoutInterval
        self.appIdentityProvider = appIdentityProvider
    }

    public func claim(
        hosts: [String],
        port: Int,
        tlsPort: Int,
        sessionId: String,
        optCode: String
    ) async throws -> QRClaimResult {
        var lastErrors: [Error] = []

        for host in hosts {
            do {
                return try await attemptClaim(
                    host: host,
                    port: port,
                    tlsPort: tlsPort,
                    sessionId: sessionId,
                    optCode: optCode
                )
            } catch {
                LocalLog.error("[QRDownload] host \(host):\(port) failed: \(error.localizedDescription)")
                lastErrors.append(error)
                trustSessionManager.reset()
                continue
            }
        }

        if let lastError = lastErrors.last as? QRTriggerDownloadClientError,
           case .httpError = lastError {
            throw lastError
        }

        throw QRTriggerDownloadClientError.allHostsFailed(lastErrors)
    }

    private func attemptClaim(
        host: String,
        port: Int,
        tlsPort: Int,
        sessionId: String,
        optCode: String
    ) async throws -> QRClaimResult {
        LocalLog.info("[QRDownload] starting pc-to-mobile flow host=\(host):\(port) session_id=\(sessionId)")

        let correlationID = UUID().uuidString
        let deviceCertPEM = try? await appIdentityProvider.selfCertificatePEM()

        try await trustHandshake(host: host, port: port, sessionId: sessionId, correlationID: correlationID)
        LocalLog.info("[QRDownload] trust handshake completed session_id=\(sessionId)")

        try await trustConfirm(
            host: host, port: port,
            sessionId: sessionId, correlationID: correlationID,
            optCode: optCode, deviceCertPEM: deviceCertPEM
        )
        LocalLog.info("[QRDownload] trust confirm completed session_id=\(sessionId)")

        let result = try await download(
            host: host, port: tlsPort,
            sessionId: sessionId, correlationID: correlationID
        )
        LocalLog.info("[QRDownload] download completed session_id=\(sessionId)")
        return result
    }

    private func trustHandshake(
        host: String,
        port: Int,
        sessionId: String,
        correlationID: String
    ) async throws {
        let mobileDHPublicKey = trustSessionManager.publicKeyBase64URL
        let mobileNonce = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).ispcBase64URLEncodedString()

        let requestBody: [String: Any] = [
            "mobile_dh_public_key": mobileDHPublicKey,
            "mobile_nonce": mobileNonce,
            "mobile_port": 1,
            "mobile_ip_list": ["127.0.0.1"],
        ]

        let urlString = "http://\(host):\(port)\(ISPCProtocol.apiPrefix)/trust/handshake"
        guard let url = URL(string: urlString) else {
            throw QRTriggerDownloadClientError.handshakeFailed("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionId, forHTTPHeaderField: "X-Session-Id")
        request.setValue(correlationID, forHTTPHeaderField: "X-Correlation-Id")
        request.timeoutInterval = timeoutInterval
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        LocalLog.debug("[QRDownload] handshake request to \(urlString)")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw QRTriggerDownloadClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QRTriggerDownloadClientError.handshakeFailed("Non-HTTP response")
        }

        guard httpResponse.statusCode == 200 else {
            let errorInfo = tryParseErrorBody(data)
            throw QRTriggerDownloadClientError.httpError(
                statusCode: httpResponse.statusCode,
                message: errorInfo.message
            )
        }

        guard let responseBody = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pcDHPublicKey = responseBody["pc_dh_public_key"] as? String,
              let pcNonce = responseBody["pc_nonce"] as? String,
              let kdfContext = responseBody["kdf_context"] as? String else {
            throw QRTriggerDownloadClientError.handshakeFailed("Invalid handshake response")
        }

        try trustSessionManager.handleHandshakeRequest(
            pcDHPublicKey: pcDHPublicKey,
            pcNonce: pcNonce,
            pcKdfContext: kdfContext,
            mobileNonce: mobileNonce
        )
    }

    private func trustConfirm(
        host: String,
        port: Int,
        sessionId: String,
        correlationID: String,
        optCode: String,
        deviceCertPEM: String?
    ) async throws {
        guard trustSessionManager.isEstablished else {
            throw QRTriggerDownloadClientError.confirmFailed("Session key not established")
        }

        var requestPayload: [String: Any] = [
            "action": "confirm",
            "opt_code": optCode,
            "peer_device_name": await UIDevice.current.name,
        ]
        if let cert = deviceCertPEM {
            requestPayload["device_certificate_pem"] = cert
        }
        let envelope = try trustSessionManager.encryptPayload(requestPayload)

        let requestBody: [String: Any] = [
            "schema": envelope.schema,
            "nonce": envelope.nonce,
            "ciphertext": envelope.ciphertext,
            "encryption_alg": "aes-256-gcm",
        ]

        let urlString = "http://\(host):\(port)\(ISPCProtocol.apiPrefix)/trust/confirm"
        guard let url = URL(string: urlString) else {
            throw QRTriggerDownloadClientError.confirmFailed("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionId, forHTTPHeaderField: "X-Session-Id")
        request.setValue(correlationID, forHTTPHeaderField: "X-Correlation-Id")
        request.timeoutInterval = timeoutInterval
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        LocalLog.debug("[QRDownload] confirm request to \(urlString)")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw QRTriggerDownloadClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QRTriggerDownloadClientError.confirmFailed("Non-HTTP response")
        }

        if httpResponse.statusCode == 403 {
            throw QRTriggerDownloadClientError.invalidOptCode
        }

        guard httpResponse.statusCode == 200 else {
            let errorInfo = tryParseErrorBody(data)
            throw QRTriggerDownloadClientError.httpError(
                statusCode: httpResponse.statusCode,
                message: errorInfo.message
            )
        }

        let responseBody = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let responseEnvelope = ISPCTrustEnvelope(
            nonce: responseBody["nonce"] as? String ?? "",
            ciphertext: responseBody["ciphertext"] as? String ?? ""
        )

        let decryptedPayload = try trustSessionManager.decryptEnvelope(responseEnvelope)
        guard let trustStatus = decryptedPayload["trust_status"] as? String,
              trustStatus == "trusted" else {
            throw QRTriggerDownloadClientError.confirmFailed("Expected trust_status=trusted")
        }

        if let pcCertPEM = decryptedPayload["device_certificate_pem"] as? String {
            do {
                try await appIdentityProvider.importPeerCertificate(pem: pcCertPEM)
                LocalLog.info("[QRDownload] imported PC certificate")
            } catch {
                LocalLog.error("[QRDownload] failed to import PC cert: \(error.localizedDescription)")
                throw QRTriggerDownloadClientError.confirmFailed(error.localizedDescription)
            }
        } else {
            throw QRTriggerDownloadClientError.confirmFailed("No peer cert")
        }
    }

    private func download(
        host: String,
        port: Int,
        sessionId: String,
        correlationID: String
    ) async throws -> QRClaimResult {
        // Step 1: Fetch manifest to discover available files
        let manifest = try await fetchManifest(host: host, port: port, sessionId: sessionId, correlationID: correlationID)

        // Step 2: Single file or multi-file?
        if manifest.fileCount == 1 {
            // Download the single file at index 0
            return try await downloadFileAtIndex(0, host: host, port: port, sessionId: sessionId, correlationID: correlationID, manifest: manifest)
        }

        // Step 3: Multi-file — return manifest so UI can drive per-file download
        return .multiFile(manifest: manifest, host: host, tlsPort: port, sessionId: sessionId, correlationID: correlationID)
    }

    /// Fetch the file manifest from /transfer/manifest.
    public func fetchManifest(
        host: String,
        port: Int,
        sessionId: String,
        correlationID: String
    ) async throws -> MultiFileManifest {
        let urlString = "https://\(host):\(port)\(ISPCProtocol.apiPrefix)\(ISPCProtocol.transferManifestPath)"
        guard let url = URL(string: urlString) else {
            throw QRTriggerDownloadClientError.downloadFailed("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(sessionId, forHTTPHeaderField: "X-Session-Id")
        request.setValue(correlationID, forHTTPHeaderField: "X-Correlation-Id")
        request.timeoutInterval = timeoutInterval

        let sigHeaders = try await signatureHeaders(for: sessionId)
        request.setValue(sigHeaders.signature, forHTTPHeaderField: "X-Session-Signature")
        request.setValue(sigHeaders.algorithm, forHTTPHeaderField: "X-Session-Signature-Alg")
        request.setValue(sigHeaders.deviceUUID, forHTTPHeaderField: "X-Peer-Device-Id")

        LocalLog.debug("[QRDownload] manifest request to \(urlString)")

        let delegate = TlsTrustDelegate(appIdentityProvider: appIdentityProvider)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request, delegate: delegate)
        } catch {
            throw QRTriggerDownloadClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QRTriggerDownloadClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 403:
            throw QRTriggerDownloadClientError.invalidOptCode
        case 404:
            throw QRTriggerDownloadClientError.stashNotFound
        case 410:
            throw QRTriggerDownloadClientError.stashExpired
        default:
            let message = parseErrorMessage(data) ?? "Server error"
            throw QRTriggerDownloadClientError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fileCount = json["file_count"] as? Int,
              let filesArray = json["files"] as? [[String: Any]] else {
            throw QRTriggerDownloadClientError.invalidResponse
        }

        let entries = filesArray.compactMap { entry -> MultiFileManifest.FileEntry? in
            guard let index = entry["index"] as? Int,
                  let type = entry["type"] as? String else {
                return nil
            }
            let contentType = entry["content_type"] as? String ?? ""
            let content = entry["content"] as? String
            let filename = entry["filename"] as? String ?? ""
            let sizeBytes = entry["size_bytes"] as? Int ?? 0
            return MultiFileManifest.FileEntry(
                index: index, type: type, filename: filename,
                contentType: contentType, sizeBytes: sizeBytes, content: content
            )
        }

        return MultiFileManifest(fileCount: fileCount, files: entries)
    }

    /// Download a single file by index from a batch stash.
    public func downloadFileAtIndex(
        _ index: Int,
        host: String,
        port: Int,
        sessionId: String,
        correlationID: String,
        manifest: MultiFileManifest? = nil
    ) async throws -> QRClaimResult {
        let urlString = "https://\(host):\(port)\(ISPCProtocol.apiPrefix)/transfer/download/\(index)"
        guard let url = URL(string: urlString) else {
            throw QRTriggerDownloadClientError.downloadFailed("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(sessionId, forHTTPHeaderField: "X-Session-Id")
        request.setValue(correlationID, forHTTPHeaderField: "X-Correlation-Id")
        request.timeoutInterval = timeoutInterval

        let sigHeaders = try await signatureHeaders(for: sessionId)
        request.setValue(sigHeaders.signature, forHTTPHeaderField: "X-Session-Signature")
        request.setValue(sigHeaders.algorithm, forHTTPHeaderField: "X-Session-Signature-Alg")
        request.setValue(sigHeaders.deviceUUID, forHTTPHeaderField: "X-Peer-Device-Id")

        LocalLog.debug("[QRDownload] download file index=\(index) from \(urlString)")

        let delegate = TlsTrustDelegate(appIdentityProvider: appIdentityProvider)
        let (tempFileURL, response): (URL, URLResponse)
        do {
            (tempFileURL, response) = try await urlSession.download(for: request, delegate: delegate)
        } catch {
            throw QRTriggerDownloadClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw QRTriggerDownloadClientError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 404:
            cleanupTempFile(tempFileURL)
            throw QRTriggerDownloadClientError.stashNotFound
        case 410:
            cleanupTempFile(tempFileURL)
            throw QRTriggerDownloadClientError.stashExpired
        default:
            let tempData = try? Data(contentsOf: tempFileURL)
            cleanupTempFile(tempFileURL)
            let message = parseErrorMessage(tempData ?? Data()) ?? "Download failed"
            throw QRTriggerDownloadClientError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        return try await parseDownloadResponse(tempFileURL: tempFileURL, response: httpResponse)
    }

    private func parseDownloadResponse(
        tempFileURL: URL,
        response: HTTPURLResponse
    ) async throws -> QRClaimResult {
        guard let contentType = response.value(forHTTPHeaderField: "Content-Type") else {
            cleanupTempFile(tempFileURL)
            throw QRTriggerDownloadClientError.invalidResponse
        }

        let lowercasedContentType = contentType.lowercased()

        if lowercasedContentType.hasPrefix("text/html") {
            let data = try Data(contentsOf: tempFileURL)
            cleanupTempFile(tempFileURL)
            guard let html = String(data: data, encoding: .utf8) else {
                throw QRTriggerDownloadClientError.invalidResponse
            }
            return .html(html)
        }

        if lowercasedContentType.hasPrefix("text/") {
            let data = try Data(contentsOf: tempFileURL)
            cleanupTempFile(tempFileURL)
            guard let text = String(data: data, encoding: .utf8) else {
                throw QRTriggerDownloadClientError.invalidResponse
            }
            return .text(text)
        }

        let filename = response.value(forHTTPHeaderField: "X-Original-Filename")

        if lowercasedContentType.hasPrefix("image/") {
            let fileURL = try persistToDocuments(tempFileURL, filename: filename, prefix: "image")
            return .image(fileURL: fileURL, contentType: contentType, filename: filename)
        }

        if lowercasedContentType == "application/octet-stream" {
            let fileURL = try persistToDocuments(tempFileURL, filename: filename, prefix: "file")
            return .file(fileURL: fileURL, contentType: contentType, filename: filename)
        }

        cleanupTempFile(tempFileURL)
        throw QRTriggerDownloadClientError.invalidResponse
    }

    private func persistToDocuments(_ tempFileURL: URL, filename: String?, prefix: String) throws -> URL {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw QRTriggerDownloadClientError.invalidResponse
        }

        let subDir = documentsDir.appendingPathComponent("QRDownloads", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)

        let rawName = filename ?? "\(prefix)_\(Int(Date().timeIntervalSince1970))"
        let fileName = rawName.drop(while: { $0 == "." }).isEmpty ? rawName : String(rawName.drop(while: { $0 == "." }))
        let destURL = subDir.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }

        try FileManager.default.moveItem(at: tempFileURL, to: destURL)
        return destURL
    }

    private func cleanupTempFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func parseErrorMessage(_ data: Data) -> String? {
        guard let decoded = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (decoded["error"] as? String) ?? (decoded["message"] as? String)
    }

    /// Builds the three app-layer signature headers for the given sessionId.
    private func signatureHeaders(for sessionId: String) async throws -> (signature: String, algorithm: String, deviceUUID: String) {
        let (signature, algorithm) = try await appIdentityProvider.signSessionID(sessionId)
        let deviceID = try await appIdentityProvider.deviceUUID()
        LocalLog.debug("[QRDownload] signature headers session_id=\(sessionId) device_uuid=\(deviceID)")
        return (signature, algorithm, deviceID)
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
