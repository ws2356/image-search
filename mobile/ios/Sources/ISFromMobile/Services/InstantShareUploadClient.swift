import Foundation
import Common

enum InstantShareUploadClientError: Error, Sendable {
    case uploadFailed(String)
    case invalidResponse(String)
    case httpError(statusCode: Int, errorCode: String, message: String)
    case networkError(Error)
    case trustRequired
    case sessionNotFound
    case tlsVerificationFailed(String)
}

extension InstantShareUploadClientError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .invalidResponse(let message):
            return "Invalid response from PC: \(message)"
        case .httpError(let statusCode, let errorCode, let message):
            return "HTTP \(statusCode): [\(errorCode)] \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .trustRequired:
            return "Trust handshake must be completed before transfer"
        case .sessionNotFound:
            return "Session not found"
        case .tlsVerificationFailed(let message):
            return "TLS verification failed: \(message)"
        }
    }
}

final class InstantShareUploadClient: Sendable {
    private let urlSession: URLSession
    private let timeoutInterval: TimeInterval
    private let appIdentityProvider: AppIdentityProviding

    init(
        urlSession: URLSession = .shared,
        timeoutInterval: TimeInterval = 30.0,
        appIdentityProvider: AppIdentityProviding
    ) {
        self.urlSession = urlSession
        self.timeoutInterval = timeoutInterval
        self.appIdentityProvider = appIdentityProvider
    }

    func uploadText(
        host: String,
        port: Int,
        sessionID: String,
        correlationID: String,
        text: String,
        peerDeviceID: String? = nil,
        peerDeviceName: String? = nil
    ) async throws {
        let requestBody: [String: Any] = ["text_utf8": text]

        let urlString = "https://\(host):\(port)\(InstantShareProtocol.apiPrefix)/transfer/text"
        LocalLog.debug("[UploadClient] uploadText URL: \(urlString) peerDeviceID=\(peerDeviceID ?? "nil")")
        guard let url = URL(string: urlString) else {
            throw InstantShareUploadClientError.uploadFailed("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionID, forHTTPHeaderField: "X-Session-Id")
        request.setValue(correlationID, forHTTPHeaderField: "X-Correlation-Id")
        request.timeoutInterval = timeoutInterval
        if let peerDeviceName {
            request.setValue(peerDeviceName, forHTTPHeaderField: "X-Peer-Device-Name")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw InstantShareUploadClientError.uploadFailed("Failed to encode request body: \(error)")
        }

        let delegate = InstantShareServerTrustDelegate(
            peerDeviceID: peerDeviceID,
            appIdentityProvider: appIdentityProvider
        )
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request, delegate: delegate)
        } catch {
            LocalLog.debug("[UploadClient] uploadText network error: \(error.localizedDescription)")
            throw InstantShareUploadClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InstantShareUploadClientError.uploadFailed("Non-HTTP response")
        }

        if httpResponse.statusCode == 403 {
            throw InstantShareUploadClientError.trustRequired
        }
        if httpResponse.statusCode == 404 {
            throw InstantShareUploadClientError.sessionNotFound
        }
        guard httpResponse.statusCode == 200 else {
            let errorInfo = tryParseErrorBody(data)
            throw InstantShareUploadClientError.httpError(
                statusCode: httpResponse.statusCode,
                errorCode: errorInfo.errorCode,
                message: errorInfo.message
            )
        }
        LocalLog.debug("[UploadClient] uploadText succeeded for \(peerDeviceID)")
    }

    func uploadImage(
        host: String,
        port: Int,
        sessionID: String,
        correlationID: String,
        imageData: Data,
        contentType: String,
        filename: String?,
        peerDeviceID: String? = nil,
        peerDeviceName: String? = nil
    ) async throws {
        let urlString = "https://\(host):\(port)\(InstantShareProtocol.apiPrefix)/transfer/image"
        LocalLog.debug("[UploadClient] uploadImage URL: \(urlString) peerDeviceID=\(peerDeviceID ?? "nil") size=\(imageData.count)")
        guard let url = URL(string: urlString) else {
            throw InstantShareUploadClientError.uploadFailed("Invalid URL: \(urlString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(sessionID, forHTTPHeaderField: "X-Session-Id")
        request.setValue(correlationID, forHTTPHeaderField: "X-Correlation-Id")
        if let filename {
            request.setValue(filename, forHTTPHeaderField: "X-Instant-Share-Filename")
        }
        if let peerDeviceName {
            request.setValue(peerDeviceName, forHTTPHeaderField: "X-Peer-Device-Name")
        }
        request.httpBody = imageData
        request.timeoutInterval = timeoutInterval

        let delegate = InstantShareServerTrustDelegate(
            peerDeviceID: peerDeviceID,
            appIdentityProvider: appIdentityProvider
        )
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await urlSession.data(for: request, delegate: delegate)
        } catch {
            LocalLog.debug("[UploadClient] uploadImage network error: \(error.localizedDescription)")
            throw InstantShareUploadClientError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw InstantShareUploadClientError.uploadFailed("Non-HTTP response")
        }

        if httpResponse.statusCode == 403 {
            throw InstantShareUploadClientError.trustRequired
        }
        if httpResponse.statusCode == 404 {
            throw InstantShareUploadClientError.sessionNotFound
        }
        guard httpResponse.statusCode == 200 else {
            let errorInfo = tryParseErrorBody(data)
            throw InstantShareUploadClientError.httpError(
                statusCode: httpResponse.statusCode,
                errorCode: errorInfo.errorCode,
                message: errorInfo.message
            )
        }
        LocalLog.debug("[UploadClient] uploadImage succeeded for \(peerDeviceID)")
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

final class InstantShareServerTrustDelegate: NSObject, URLSessionTaskDelegate {
    private let peerDeviceID: String?
    private let appIdentityProvider: AppIdentityProviding

    init(peerDeviceID: String?, appIdentityProvider: AppIdentityProviding) {
        self.peerDeviceID = peerDeviceID
        self.appIdentityProvider = appIdentityProvider
        LocalLog.debug("[TLS] InstantShareServerTrustDelegate created for peer=\(peerDeviceID ?? "nil")")
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            handleServerTrustChallenge(challenge, completionHandler: completionHandler)
        case NSURLAuthenticationMethodClientCertificate:
            handleClientCertificateChallenge(completionHandler: completionHandler)
        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }

    private func handleServerTrustChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        LocalLog.debug("[TLS] received serverTrust challenge for \(peerDeviceID)")

        let count = SecTrustGetCertificateCount(serverTrust)
        guard count > 0, let serverCert = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            LocalLog.error("[TLS] no certificate in server trust chain")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let serverCN = SecCertificateCopySubjectSummary(serverCert) as String? else {
            LocalLog.error("[TLS] failed to extract CN from server cert")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        LocalLog.debug("[TLS] server cert CN=\(serverCN) peerDeviceID=\(peerDeviceID)")

        let storedCert: SecCertificate
        do {
            storedCert = try appIdentityProvider.peerCertificate(for: serverCN)
            LocalLog.debug("[TLS] loaded stored peer certificate by CN=\(serverCN)")
        } catch {
            if let peerDeviceID, !peerDeviceID.isEmpty {
                LocalLog.debug("[TLS] lookup by CN failed, trying peerDeviceID=\(peerDeviceID)")
                do {
                    storedCert = try appIdentityProvider.peerCertificate(for: peerDeviceID)
                    LocalLog.debug("[TLS] loaded stored peer certificate by key=\(peerDeviceID)")
                } catch {
                    LocalLog.error("[TLS] no stored peer certificate for CN=\(serverCN) or key=\(peerDeviceID)")
                    completionHandler(.cancelAuthenticationChallenge, nil)
                    return
                }
            } else {
                LocalLog.error("[TLS] no stored peer certificate for CN=\(serverCN) and no peerDeviceID")
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }

        guard let serverPubKey = SecCertificateCopyKey(serverCert) else {
            LocalLog.error("[TLS] failed to copy public key from server cert")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        guard let serverPubKeyData = serverPubKey.externalRepresentation else {
            LocalLog.error("[TLS] failed to export server public key bytes")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard let storedPubKey = SecCertificateCopyKey(storedCert) else {
            LocalLog.error("[TLS] failed to copy public key from stored cert")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        guard let storedPubKeyData = storedPubKey.externalRepresentation else {
            LocalLog.error("[TLS] failed to export stored public key bytes")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        guard serverPubKeyData == storedPubKeyData else {
            LocalLog.error("[TLS] public key mismatch for \(peerDeviceID)")
            LocalLog.debug("[TLS] server pubKey=\(serverPubKeyData.base64EncodedString())")
            LocalLog.debug("[TLS] stored pubKey=\(storedPubKeyData.base64EncodedString())")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        // 🔴 核心步骤：关闭域名/IP校验
        // 默认系统创建的 policy 绑定了当前的请求域名（比如 "192.168.1.100"）
        // 我们重新创建一个不需要校验 Hostname 的基础客户端 SSL 策略
        let policy = SecPolicyCreateSSL(false, nil) // false 表示不作为服务器，nil 表示不校验 hostname
        
        // 将这个无域名校验的策略覆盖到当前连接的 serverTrust 中
        SecTrustSetPolicies(serverTrust, policy)

        // 3. 核心魔法：把本地存储的证书设置为本次 TLS 的“信任锚点 (Anchor)”
        // 这样 iOS 底层就会把你的自签名证书当成顶级 CA 来对待
        let anchors = [serverCert] as CFArray
        SecTrustSetAnchorCertificates(serverTrust, anchors)
        
        // 4. 关键安全设置：告诉 iOS【只】信任我指定的锚点，忽略系统自带的那些权威 CA（如 DigiCert 等）
        // 这能彻底防止中间人拿着一张合法的公网证书来假冒你的局域网 PC
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)
        

        LocalLog.debug("[TLS] public keys match, evaluating trust...")
        var error: CFError?
        let trusted = SecTrustEvaluateWithError(serverTrust, &error)
        if trusted {
            LocalLog.debug("[TLS] trust evaluation passed for \(peerDeviceID)")
            let credential = URLCredential(trust: serverTrust)
            completionHandler(.useCredential, credential)
        } else {
            let errDesc = error?.localizedDescription ?? "unknown error"
            LocalLog.error("[TLS] trust evaluation failed: \(errDesc)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    private func handleClientCertificateChallenge(
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        LocalLog.debug("[TLS] received client certificate challenge")
        do {
            let identity = try appIdentityProvider.selfIdentity()
            let cert = try appIdentityProvider.selfCertificate()
            LocalLog.debug("[TLS] providing client identity for mTLS")
            let credential = URLCredential(
                identity: identity,
                certificates: [cert],
                persistence: .forSession
            )
            completionHandler(.useCredential, credential)
        } catch {
            LocalLog.error("[TLS] failed to get client identity: \(error.localizedDescription)")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}

private extension SecKey {
    var externalRepresentation: Data? {
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(self, &error) as Data? else {
            if let err = error?.takeRetainedValue() {
                LocalLog.error("[TLS] SecKeyCopyExternalRepresentation failed: \(err.localizedDescription)")
            }
            return nil
        }
        return data
    }
}
