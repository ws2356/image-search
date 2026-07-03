//
//  IdentityClient.swift
//  ISFromMobile
//
//  TCA dependency client wrapping AppIdentityProviding and LocalDeviceIdentifierProviding.
//  Factory bridge via Container.shared — these are cross-target singletons.
//
import ComposableArchitecture
import Common
import Factory
import Foundation

@DependencyClient
struct IdentityClient {
    var selfCertificatePEM: @Sendable () async throws -> String = { "" }
    var importPeerCertificate: @Sendable (_ pem: String) async throws -> Void
    var ensureSelfIdentity: @Sendable () async throws -> Void
    var currentDeviceName: @Sendable () async -> String = { "" }
    var deviceUUID: @Sendable () async throws -> String = { "" }
}

extension IdentityClient: DependencyKey {
    static let liveValue = IdentityClient(
        selfCertificatePEM: { try await Container.shared.appIdentityProvider().selfCertificatePEM() },
        importPeerCertificate: { try await Container.shared.appIdentityProvider().importPeerCertificate(pem: $0) },
        ensureSelfIdentity: { try await Container.shared.appIdentityProvider().ensureSelfIdentity() },
        currentDeviceName: { await Container.shared.localDeviceIdentityProvider().currentIdentifier().deviceName },
        deviceUUID: { try await Container.shared.appIdentityProvider().deviceUUID() }
    )
}

extension DependencyValues {
    var identityClient: IdentityClient {
        get { self[IdentityClient.self] }
        set { self[IdentityClient.self] = newValue }
    }
}
