//
//  TrustClient.swift
//  ISFromMobile
//
//  TCA dependency client wrapping InstantShareTrustClient.
//  Singleton in liveValue — InstantShareTrustClient has no mutable state of its own
//  (all let properties). @unchecked Sendable is only because the shared
//  trustSessionManager reference is a mutable class, which is itself a singleton.
//  The singleton captures the same InstantShareTrustSessionManager instance used
//  by TrustSessionManagerClient.liveValue.
//
import ComposableArchitecture
import Common
import Foundation

@DependencyClient
struct TrustClient {
    var handshake: @Sendable (
        _ hosts: [String],
        _ port: Int,
        _ sessionID: String,
        _ correlationID: String,
        _ mobilePort: Int,
        _ mobileIPList: [String],
        _ payloadClass: String,
        _ targetIntent: String,
        _ trustMode: String
    ) async throws -> InstantShareTrustHandshakeResponse

    var apply: @Sendable (
        _ hosts: [String],
        _ port: Int,
        _ sessionID: String,
        _ correlationID: String
    ) async throws -> Void

    var confirm: @Sendable (
        _ hosts: [String],
        _ port: Int,
        _ sessionID: String,
        _ correlationID: String,
        _ pinCode: String,
        _ deviceCertificatePEM: String?
    ) async throws -> String?
}

extension TrustClient: DependencyKey {
    static let liveValue = {
        // Share the same trust session manager instance used by TrustSessionManagerClient
        let manager = TrustSessionManagerClient._liveManager
        let client = InstantShareTrustClient(trustSessionManager: manager)
        return TrustClient(
            handshake: { try await client.handshake(
                hosts: $0, port: $1, sessionID: $2, correlationID: $3,
                mobilePort: $4, mobileIPList: $5, payloadClass: $6,
                targetIntent: $7, trustMode: $8
            ) },
            apply: { try await client.apply(
                hosts: $0, port: $1, sessionID: $2, correlationID: $3
            ) },
            confirm: { try await client.confirm(
                hosts: $0, port: $1, sessionID: $2, correlationID: $3,
                pinCode: $4, deviceCertificatePEM: $5
            ) }
        )
    }()
}

extension DependencyValues {
    var trustClient: TrustClient {
        get { self[TrustClient.self] }
        set { self[TrustClient.self] = newValue }
    }
}
