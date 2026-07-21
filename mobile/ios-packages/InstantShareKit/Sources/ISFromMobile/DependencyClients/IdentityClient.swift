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
public struct IdentityClient : Sendable {
    public let selfCertificatePEM: @Sendable () async throws -> String
    public let importPeerCertificate: @Sendable (_ pem: String) async throws -> Void
    public let initialize: @Sendable () async throws -> Void
    public let currentDeviceName: @Sendable () async -> String
    public let deviceUUID: @Sendable () async throws -> String
    
    public init(
        selfCertificatePEM: @Sendable @escaping () async throws -> String,
        importPeerCertificate: @Sendable @escaping (_: String) async throws -> Void,
        initialize: @Sendable @escaping () async throws -> Void,
        currentDeviceName: @Sendable @escaping () async -> String,
        deviceUUID: @Sendable @escaping () async throws -> String
    ) {
        self.selfCertificatePEM = selfCertificatePEM
        self.importPeerCertificate = importPeerCertificate
        self.initialize = initialize
        self.currentDeviceName = currentDeviceName
        self.deviceUUID = deviceUUID
    }
}

extension IdentityClient: DependencyKey {
    public static let liveValue = IdentityClient(
        selfCertificatePEM: { try await Container.shared.appIdentityProvider().selfCertificatePEM() },
        importPeerCertificate: { try await Container.shared.appIdentityProvider().importPeerCertificate(pem: $0) },
        initialize: { try await Container.shared.appIdentityProvider().initialize() },
        currentDeviceName: { await Container.shared.localDeviceIdentityProvider().currentIdentifier().deviceName },
        deviceUUID: { try await Container.shared.appIdentityProvider().deviceUUID() }
    )
}

extension DependencyValues {
    public var identityClient: IdentityClient {
        get { self[IdentityClient.self] }
        set { self[IdentityClient.self] = newValue }
    }
}
