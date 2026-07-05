import ComposableArchitecture
import Common
import Factory
import Foundation

@DependencyClient
struct DeviceManagementClient {
    var loadDevices: @Sendable () async throws -> [TrustedDevice] = { [] }
    var deleteDevice: @Sendable (_ pubkeyHash: Data) async throws -> Void
}

extension DeviceManagementClient: DependencyKey {
    static let liveValue = DeviceManagementClient(
        loadDevices: {
            let provider = Container.shared.appIdentityProvider()
            let certs = try await provider.loadAllPeerCertificates()
            LocalLog.debug("[dm] loaded certs: \(certs)")
            return certs.compactMap { cert in
                guard let name = cert.commonName,
                      let id = cert.deviceUUIDFromExtension(KeychainAppIdentityProvider.deviceIdOID),
                      let hash = cert.publicKeyHash
                else { return nil }
                return TrustedDevice(id: id, name: name, pubkeyHash: hash)
            }
        },
        deleteDevice: { hash in
            let provider = Container.shared.appIdentityProvider()
            try await provider.deletePeerCertificate(forPubkeyHash: hash)
        }
    )
}

extension DependencyValues {
    var deviceManagement: DeviceManagementClient {
        get { self[DeviceManagementClient.self] }
        set { self[DeviceManagementClient.self] = newValue }
    }
}
