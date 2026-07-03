//
//  TrustSessionManagerClient.swift
//  ISFromMobile
//
//  TCA dependency client wrapping InstantShareTrustSessionManager.
//  Singleton in liveValue — replaces InstantShareService's ownership of the trust
//  session manager. Exposes reset() for cleanup between sessions.
//  Exposes _liveManager for sharing the same manager instance with TrustClient.
//
import ComposableArchitecture
import Common
import Foundation

@DependencyClient
struct TrustSessionManagerClient {
    /// Whether a handshake has been completed and a session key is available.
    var isEstablished: @Sendable () -> Bool = { false }

    /// Handle an incoming trust handshake request, deriving a session key.
    var handleHandshakeRequest: @Sendable (
        _ pcDHPublicKey: String,
        _ pcNonce: String,
        _ pcKdfContext: String,
        _ mobileNonce: String
    ) throws -> InstantShareTrustHandshakeResponse

    /// Decrypt a trust envelope using the established session key.
    var decryptEnvelope: @Sendable (_ envelope: InstantShareTrustEnvelope) throws -> [String: Any]

    /// Encrypt a response payload as a trust envelope using the established session key.
    var encryptResponse: @Sendable (_ payload: [String: Any]) throws -> InstantShareTrustEnvelope

    /// Reset the session manager for a new session (regenerates keypair, clears session key).
    var reset: @Sendable () -> Void

    /// The underlying manager instance, shared with TrustClient.
    static nonisolated(unsafe) let _liveManager = InstantShareTrustSessionManager()
}

extension TrustSessionManagerClient: DependencyKey {
    static let liveValue = {
        let manager = _liveManager
        return TrustSessionManagerClient(
            isEstablished: { manager.isEstablished },
            handleHandshakeRequest: { try manager.handleHandshakeRequest(
                pcDHPublicKey: $0, pcNonce: $1, pcKdfContext: $2, mobileNonce: $3
            ) },
            decryptEnvelope: { try manager.decryptEnvelope($0) },
            encryptResponse: { try manager.encryptResponse($0) },
            reset: { manager.reset() }
        )
    }()
}

extension DependencyValues {
    var trustSessionManager: TrustSessionManagerClient {
        get { self[TrustSessionManagerClient.self] }
        set { self[TrustSessionManagerClient.self] = newValue }
    }
}
