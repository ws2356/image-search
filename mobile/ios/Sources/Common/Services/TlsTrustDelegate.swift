//
//  TlsTrustDelegate.swift
//  AlbumTransporterKit
//
//  Created by Song Wan on 2026/6/20.
//
import Foundation

public final class TlsTrustDelegate: NSObject, URLSessionTaskDelegate {
    private let appIdentityProvider: AppIdentityProviding

    public init(appIdentityProvider: AppIdentityProviding) {
        self.appIdentityProvider = appIdentityProvider
        LocalLog.debug("[TLS] TlsTrustDelegate created")
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        Task {
            switch challenge.protectionSpace.authenticationMethod {
            case NSURLAuthenticationMethodServerTrust:
                await handleServerTrustChallenge(challenge, completionHandler: completionHandler)
            case NSURLAuthenticationMethodClientCertificate:
                handleClientCertificateChallenge(completionHandler: completionHandler)
            default:
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }

    private func handleServerTrustChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) async {
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        LocalLog.debug("[TLS] received serverTrust challenge")

        let count = SecTrustGetCertificateCount(serverTrust)
        guard count > 0, let serverCert = SecTrustGetCertificateAtIndex(serverTrust, 0) else {
            LocalLog.error("[TLS] no certificate in server trust chain")
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let pubkeyHash = serverCert.publicKeyHash else {
            LocalLog.error("[TLS] failed to extract publicKeyHash from server cert")
            completionHandler(.performDefaultHandling, nil)
            return
        }
        LocalLog.debug("[TLS] server cert pubkeyHash=\(pubkeyHash.base64EncodedString())")

        guard let storedCert = try? await appIdentityProvider.peerCertificate(forPubkeyHash: pubkeyHash) else {
            LocalLog.error("[TLS] no stored peer certificate for pubkeyHash")
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let serverPubKey = SecCertificateCopyKey(serverCert) else {
            LocalLog.error("[TLS] failed to copy public key from server cert")
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let serverPubKeyData = serverPubKey.externalRepresentation else {
            LocalLog.error("[TLS] failed to export server public key bytes")
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard let storedPubKey = SecCertificateCopyKey(storedCert) else {
            LocalLog.error("[TLS] failed to copy public key from stored cert")
            completionHandler(.performDefaultHandling, nil)
            return
        }
        guard let storedPubKeyData = storedPubKey.externalRepresentation else {
            LocalLog.error("[TLS] failed to export stored public key bytes")
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard serverPubKeyData == storedPubKeyData else {
            LocalLog.error("[TLS] public key mismatch")
            LocalLog.debug("[TLS] server pubKey=\(serverPubKeyData.base64EncodedString())")
            LocalLog.debug("[TLS] stored pubKey=\(storedPubKeyData.base64EncodedString())")
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let policy = SecPolicyCreateSSL(false, nil)
        SecTrustSetPolicies(serverTrust, policy)

        let anchors = [serverCert] as CFArray
        SecTrustSetAnchorCertificates(serverTrust, anchors)
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)

        LocalLog.debug("[TLS] public keys match, evaluating trust...")
        var error: CFError?
        let trusted = SecTrustEvaluateWithError(serverTrust, &error)
        if trusted {
            LocalLog.debug("[TLS] trust evaluation passed")
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
        LocalLog.debug("[TLS] received client certificate challenge — app-layer auth used instead")
        completionHandler(.performDefaultHandling, nil)
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
