import CryptoKit
import Foundation

/// Manages the ephemeral DH keypair and derived AES-GCM session key for a
/// single instant-share trust session.
///
/// Mirrors the PC-side `X25519TrustSessionKeyResolver`:
/// uses X25519 ECDH with HKDF-SHA256 (salt = pc_nonce || mobile_nonce, info =
/// "dtis.instant-share.trust-session.v1" || kdf_context) to derive a 256-bit
/// AES-GCM session key.
final class InstantShareTrustSessionManager: @unchecked Sendable {
    private let lock = NSLock()
    private var privateKey: Curve25519.KeyAgreement.PrivateKey
    private(set) var publicKeyBase64URL: String
    private var sessionKey: SymmetricKey?

    init() {
        let ephemeralKey = Curve25519.KeyAgreement.PrivateKey()
        self.privateKey = ephemeralKey
        self.publicKeyBase64URL = ephemeralKey.publicKey.rawRepresentation
            .instantShareBase64URLEncodedString()
    }

    /// Returns the mobile-side handshake response payload, derived from the
    /// PC's DH public key and nonce via X25519 + HKDF.
    func handleHandshakeRequest(
        pcDHPublicKey: String,
        pcNonce: String
    ) throws -> InstantShareTrustHandshakeResponse {
        lock.lock()
        defer { lock.unlock() }

        let pcPublicKeyData = try Data(instantShareBase64URLEncoded: pcDHPublicKey)
        guard pcPublicKeyData.count == 32 else {
            throw InstantShareServiceError.invalidTrustEnvelopeField("pc_dh_public_key")
        }
        let pcNonceData = try Data(instantShareBase64URLEncoded: pcNonce)
        guard pcNonceData.count == 32 else {
            throw InstantShareServiceError.invalidTrustEnvelopeField("pc_nonce")
        }

        let pcPublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: pcPublicKeyData)
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: pcPublicKey)

        // Generate mobile nonce and kdf_context
        let mobileNonce = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        let kdfContext = Data((0..<32).map { _ in UInt8.random(in: 0...255) })

        // Derive session key: HKDF-SHA256(
        //   ikm = sharedSecret,
        //   salt = pc_nonce || mobile_nonce,
        //   info = "dtis.instant-share.trust-session.v1" || kdf_context,
        //   L = 32
        // )
        let derivedKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: pcNonceData + mobileNonce,
            sharedInfo: Data("dtis.instant-share.trust-session.v1".utf8) + kdfContext,
            outputByteCount: 32
        )
        self.sessionKey = derivedKey

        return InstantShareTrustHandshakeResponse(
            mobileDHPublicKey: privateKey.publicKey.rawRepresentation.instantShareBase64URLEncodedString(),
            mobileNonce: mobileNonce.instantShareBase64URLEncodedString(),
            kdfContext: kdfContext.instantShareBase64URLEncodedString()
        )
    }

    /// Decrypts a trust session envelope (encrypted with the shared session key).
    func decryptEnvelope(_ envelope: InstantShareTrustEnvelope) throws -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }

        guard let sessionKey else {
            throw InstantShareServiceError.decryptionFailed
        }
        return try InstantShareTrustSessionProtector.decryptPayloadObject(envelope, sessionKey: sessionKey)
    }

    /// Encrypts a response payload with the shared session key as a trust envelope.
    func encryptResponse(_ payload: [String: Any]) throws -> InstantShareTrustEnvelope {
        lock.lock()
        defer { lock.unlock() }

        guard let sessionKey else {
            throw InstantShareServiceError.invalidTrustEnvelope
        }
        return try InstantShareTrustSessionProtector.encryptPayloadObject(
            payload,
            sessionKey: sessionKey,
            nonceData: nil
        )
    }

    /// Whether a handshake has been completed and a session key is available.
    var isEstablished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sessionKey != nil
    }

    /// Reset state for a new session.
    func reset() {
        lock.lock()
        defer { lock.unlock() }
        let ephemeralKey = Curve25519.KeyAgreement.PrivateKey()
        privateKey = ephemeralKey
        publicKeyBase64URL = ephemeralKey.publicKey.rawRepresentation
            .instantShareBase64URLEncodedString()
        sessionKey = nil
    }
}
