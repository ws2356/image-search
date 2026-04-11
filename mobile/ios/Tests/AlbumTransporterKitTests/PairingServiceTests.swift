import Foundation
import XCTest
@testable import AlbumTransporterKit

final class PairingServiceTests: XCTestCase {
    func test_pairing_decoder_accepts_fractional_second_response_dates() throws {
        let responseData = """
        {
          "schema": "dtis.mobile-pairing.v1",
          "status": "accepted",
          "message": "Pairing accepted for Alice iPhone.",
          "session_id": "pairing-demo-001",
          "desktop_device_id": "desktop-device-001",
          "desktop_name": "Studio Mac",
          "device_uuid": "ios-device-001",
          "folder_id": 1,
          "folder_path": "/Users/demo/Alice iPhone",
          "transport": "lan",
          "paired_at": "2026-04-10T16:23:04.577047+00:00",
          "server_nonce": "server-nonce-001"
        }
        """.data(using: .utf8)!

        let decodedResponse = try JSONDecoder.pairingDecoder.decode(PairingClaimResponse.self, from: responseData)

        XCTAssertEqual(decodedResponse.schema, PairingProtocol.schema)
        XCTAssertEqual(decodedResponse.status, .accepted)
        XCTAssertEqual(decodedResponse.sessionID, "pairing-demo-001")
        XCTAssertEqual(decodedResponse.desktopName, "Studio Mac")
        XCTAssertEqual(decodedResponse.pairedAt?.timeIntervalSince1970 ?? 0, 1_775_838_184.577, accuracy: 0.001)
    }

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
            trustedDesktopStore: trustedDesktopStore
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

    func test_desktop_bootstrap_pairing_service_maps_expired_desktop_response() async {
        let service = DesktopBootstrapPairingService(
            bootstrapClient: StaticPairingBootstrapClient(
                response: PairingClaimResponse(
                    schema: PairingProtocol.schema,
                    status: .expired,
                    message: "This QR code expired on desktop. Refresh and scan again.",
                    sessionID: nil,
                    desktopDeviceID: nil,
                    desktopName: nil,
                    deviceUUID: nil,
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
            trustedDesktopStore: InMemoryTrustedDesktopStore()
        )

        let result = await service.startPairing(using: .demo)

        XCTAssertEqual(result.phase, .expired)
        XCTAssertEqual(result.message, "This QR code expired on desktop. Refresh and scan again.")
    }
}

private struct StaticPairingBootstrapClient: PairingBootstrapClient {
    let response: PairingClaimResponse

    func claimPairing(at endpoint: URL, request: PairingClaimRequest) async throws -> PairingClaimResponse {
        XCTAssertEqual(endpoint.absoluteString, PairingQRCodePayload.demo.bootstrapURL.absoluteString)
        XCTAssertEqual(request.sessionID, PairingQRCodePayload.demo.sessionID)
        XCTAssertEqual(request.oneTimePasscode, PairingQRCodePayload.demo.oneTimePasscode)
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
