import Foundation
import XCTest
@testable import AlbumTransporterKit

final class PairingServiceTests: XCTestCase {
    func test_desktop_bootstrap_pairing_service_persists_trusted_desktop_record() async {
        let trustedDesktopStore = InMemoryTrustedDesktopStore()
        let service = DesktopBootstrapPairingService(
            bootstrapClient: StaticPairingBootstrapClient(
                response: PairingClaimResponse(
                    schema: PairingProtocol.schema,
                    status: .accepted,
                    message: "Pairing accepted for Alice iPhone.",
                    sessionID: "pairing-demo-001",
                    desktopDeviceID: "desktop-device-001",
                    desktopName: "Studio Mac",
                    deviceUUID: "ios-device-001",
                    folderID: 1,
                    folderPath: "/Users/demo/Alice iPhone",
                    transport: "lan",
                    pairedAt: Date(timeIntervalSince1970: 1_776_123_610),
                    serverNonce: "server-nonce-001"
                )
            ),
            identityProvider: StaticLocalDeviceIdentityProvider(
                identity: LocalDeviceIdentity(
                    installID: "install-001",
                    deviceUUID: "ios-device-001",
                    deviceName: "Alice iPhone",
                    platform: "ios"
                )
            ),
            trustedDesktopStore: trustedDesktopStore,
            now: { Date(timeIntervalSince1970: 1_776_123_000) }
        )

        let result = await service.startPairing(using: .demo)
        let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop()

        XCTAssertEqual(result.phase, .paired)
        XCTAssertEqual(result.desktopName, "Studio Mac")
        XCTAssertEqual(result.sessionID, "pairing-demo-001")
        XCTAssertEqual(result.transport, .lan)
        XCTAssertEqual(trustedDesktop?.desktopDeviceID, "desktop-device-001")
        XCTAssertEqual(trustedDesktop?.desktopName, "Studio Mac")
        XCTAssertEqual(trustedDesktop?.mobileDeviceUUID, "ios-device-001")
        XCTAssertEqual(trustedDesktop?.transport, .lan)
        XCTAssertEqual(trustedDesktop?.lastSessionID, "pairing-demo-001")
        XCTAssertFalse(trustedDesktop?.sharedKeyBase64.isEmpty ?? true)
    }

    func test_desktop_bootstrap_pairing_service_marks_expired_payloads_before_network_call() async {
        let service = DesktopBootstrapPairingService(
            bootstrapClient: StaticPairingBootstrapClient(
                response: PairingClaimResponse(
                    schema: PairingProtocol.schema,
                    status: .accepted,
                    message: "should not be used",
                    sessionID: "unused",
                    desktopDeviceID: "unused",
                    desktopName: "unused",
                    deviceUUID: "unused",
                    folderID: nil,
                    folderPath: nil,
                    transport: nil,
                    pairedAt: nil,
                    serverNonce: nil
                )
            ),
            identityProvider: StaticLocalDeviceIdentityProvider(
                identity: LocalDeviceIdentity(
                    installID: "install-001",
                    deviceUUID: "ios-device-001",
                    deviceName: "Alice iPhone",
                    platform: "ios"
                )
            ),
            trustedDesktopStore: InMemoryTrustedDesktopStore(),
            now: { Date(timeIntervalSince1970: 1_776_123_700) }
        )

        let result = await service.startPairing(using: .demo)

        XCTAssertEqual(result.phase, .expired)
    }
}

private struct StaticPairingBootstrapClient: PairingBootstrapClient {
    let response: PairingClaimResponse

    func claimPairing(at endpoint: URL, request: PairingClaimRequest) async throws -> PairingClaimResponse {
        XCTAssertEqual(endpoint.absoluteString, PairingQRCodePayload.demo.bootstrapURL.absoluteString)
        XCTAssertEqual(request.pairingID, PairingQRCodePayload.demo.pairingID)
        XCTAssertEqual(request.tokenID, PairingQRCodePayload.demo.tokenID)
        XCTAssertEqual(request.deviceUUID, "ios-device-001")
        return response
    }
}

private struct StaticLocalDeviceIdentityProvider: LocalDeviceIdentityProviding {
    let identity: LocalDeviceIdentity

    func currentIdentity() async -> LocalDeviceIdentity {
        identity
    }
}

private actor InMemoryTrustedDesktopStore: TrustedDesktopStore {
    private var record: TrustedDesktopRecord?

    func loadTrustedDesktop() async -> TrustedDesktopRecord? {
        record
    }

    func saveTrustedDesktop(_ record: TrustedDesktopRecord) async {
        self.record = record
    }
}
