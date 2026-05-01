import Foundation
import XCTest
@testable import AlbumTransporterKit

final class PairingServiceTests: XCTestCase {
    func test_pairing_decoder_accepts_fractional_second_response_dates() throws {
        let responseData = """
        {
          "schema": "dtis.mobile-pairing.v1",
          "backup_state": "pairing_completed",
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
        XCTAssertEqual(decodedResponse.backupState, .pairingCompleted)
        XCTAssertEqual(decodedResponse.sessionID, "pairing-demo-001")
        XCTAssertEqual(decodedResponse.desktopName, "Studio Mac")
        XCTAssertEqual(decodedResponse.pairedAt?.timeIntervalSince1970 ?? 0, 1_775_838_184.577, accuracy: 0.001)
    }

    func test_normalized_desktop_display_name_strips_local_suffix() {
        XCTAssertEqual(normalizedDesktopDisplayName("Studio-MacBook-Pro.local"), "Studio-MacBook-Pro")
        XCTAssertEqual(normalizedDesktopDisplayName("Studio Mac"), "Studio Mac")
        XCTAssertNil(normalizedDesktopDisplayName(nil))
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
                    desktopName: "Studio Mac.local",
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
        XCTAssertEqual(result.backupFlowState, .pairingCompleted)
        XCTAssertEqual(result.desktopName, "Studio Mac")
        XCTAssertEqual(result.sessionID, "pairing-demo-001")
        XCTAssertEqual(result.transport, .lan)
        XCTAssertEqual(trustedDesktop?.desktopDeviceID, "desktop-device-001")
        XCTAssertEqual(trustedDesktop?.desktopName, "Studio Mac")
        XCTAssertEqual(trustedDesktop?.mobileDeviceUUID, "ios-device-001")
        XCTAssertEqual(trustedDesktop?.transport, .lan)
        XCTAssertEqual(trustedDesktop?.lastSessionID, "pairing-demo-001")
        XCTAssertEqual(trustedDesktop?.usbOneTimePasscode, PairingQRCodePayload.demo.oneTimePasscode)
        XCTAssertEqual(trustedDesktop?.usbSuggestedPort, PairingQRCodePayload.demo.suggestedUSBPort)
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

    func test_desktop_bootstrap_pairing_service_retries_next_advertised_endpoint() async {
        let trustedDesktopStore = InMemoryTrustedDesktopStore()
        let bootstrapClient = RetryingPairingBootstrapClient(
            scriptedResults: [
                "http://192.168.50.17:38933/api/mobile/pairing/claim": .failure(
                    .transport(message: "The network connection was lost.")
                ),
                "http://10.0.0.5:38933/api/mobile/pairing/claim": .success(
                    PairingClaimResponse(
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
            ]
        )
        let service = DesktopBootstrapPairingService(
            bootstrapClient: bootstrapClient,
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
        let payload = PairingQRCodePayload(
            schemaVersion: 1,
            endpointTargets: ["192.168.50.17:38933", "10.0.0.5:38933"],
            sessionID: "pairing-demo-001",
            oneTimePasscode: "482913"
        )

        let result = await service.startPairing(using: payload)
        let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop()
        let requestedEndpoints = await bootstrapClient.requestedEndpoints()

        XCTAssertEqual(result.phase, .paired)
        XCTAssertEqual(result.backupFlowState, .pairingCompleted)
        XCTAssertEqual(
            requestedEndpoints,
            [
                "http://192.168.50.17:38933/api/mobile/pairing/claim",
                "http://10.0.0.5:38933/api/mobile/pairing/claim",
            ]
        )
        XCTAssertEqual(
            trustedDesktop?.endpointURL.absoluteString,
            "http://10.0.0.5:38933/api/mobile/pairing/claim"
        )
    }

    func test_desktop_bootstrap_pairing_service_prefers_usb_when_available() async {
        let trustedDesktopStore = InMemoryTrustedDesktopStore()
        let lanClient = RetryingPairingBootstrapClient(scriptedResults: [:])
        let usbClient = StaticUSBPairingBootstrapClient(
            result: .success(
                PairingClaimResponse(
                    schema: PairingProtocol.schema,
                    status: .accepted,
                    message: "Pairing accepted over USB.",
                    sessionID: "pairing-demo-001",
                    desktopDeviceID: "desktop-device-001",
                    desktopName: "Studio Mac",
                    deviceUUID: "ios-device-001",
                    folderID: 1,
                    folderPath: "/Users/demo/Alice iPhone",
                    transport: "usb",
                    pairedAt: Date(timeIntervalSince1970: 1_776_123_610),
                    serverNonce: "server-nonce-usb"
                )
            )
        )
        let service = DesktopBootstrapPairingService(
            bootstrapClient: lanClient,
            usbBootstrapClient: usbClient,
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
        let lanRequestedEndpoints = await lanClient.requestedEndpoints()
        let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop()

        XCTAssertEqual(result.phase, .paired)
        XCTAssertEqual(result.backupFlowState, .pairingCompleted)
        XCTAssertEqual(result.transport, .usb)
        XCTAssertEqual(lanRequestedEndpoints, [])
        XCTAssertEqual(trustedDesktop?.transport, .usb)
    }

    func test_desktop_bootstrap_pairing_service_falls_back_to_lan_after_usb_transport_failure() async {
        let trustedDesktopStore = InMemoryTrustedDesktopStore()
        let lanClient = RetryingPairingBootstrapClient(
            scriptedResults: [
                "http://127.0.0.1:38933/api/mobile/pairing/claim": .success(
                    PairingClaimResponse(
                        schema: PairingProtocol.schema,
                        status: .accepted,
                        message: "Pairing accepted over LAN fallback.",
                        sessionID: "pairing-demo-001",
                        desktopDeviceID: "desktop-device-001",
                        desktopName: "Studio Mac",
                        deviceUUID: "ios-device-001",
                        folderID: 1,
                        folderPath: "/Users/demo/Alice iPhone",
                        transport: "lan",
                        pairedAt: Date(timeIntervalSince1970: 1_776_123_610),
                        serverNonce: "server-nonce-lan"
                    )
                ),
            ]
        )
        let usbClient = StaticUSBPairingBootstrapClient(
            result: .failure(.transport(message: "USB websocket did not connect in time."))
        )
        let service = DesktopBootstrapPairingService(
            bootstrapClient: lanClient,
            usbBootstrapClient: usbClient,
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
        let lanRequestedEndpoints = await lanClient.requestedEndpoints()
        let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop()

        XCTAssertEqual(result.phase, .paired)
        XCTAssertEqual(result.backupFlowState, .pairingCompleted)
        XCTAssertEqual(result.transport, .lan)
        XCTAssertEqual(lanRequestedEndpoints, ["http://127.0.0.1:38933/api/mobile/pairing/claim"])
        XCTAssertEqual(trustedDesktop?.transport, .lan)
    }

    func test_desktop_bootstrap_pairing_service_polls_pairing_state_until_completed_after_mismatch() async {
        let trustedDesktopStore = InMemoryTrustedDesktopStore()
        let bootstrapClient = PollingPairingBootstrapClient(
            claimResponse: PairingClaimResponse(
                schema: PairingProtocol.schema,
                status: .rejected,
                pairingState: .pairingMismatched,
                message: "Pairing mismatch detected.",
                sessionID: "pairing-demo-001",
                desktopDeviceID: nil,
                desktopName: "Studio Mac",
                deviceUUID: "ios-device-001",
                folderID: nil,
                folderPath: nil,
                transport: "lan",
                pairedAt: nil,
                serverNonce: nil
            ),
            stateResponses: [
                PairingClaimResponse(
                    schema: PairingProtocol.schema,
                    status: .accepted,
                    pairingState: .pairingCompleted,
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
                ),
            ]
        )
        let service = DesktopBootstrapPairingService(
            bootstrapClient: bootstrapClient,
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
        let stateRequestCount = await bootstrapClient.stateRequestCount()
        let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop()

        XCTAssertEqual(result.phase, .paired)
        XCTAssertEqual(result.backupFlowState, .pairingCompleted)
        XCTAssertEqual(stateRequestCount, 1)
        XCTAssertEqual(trustedDesktop?.desktopDeviceID, "desktop-device-001")
    }

    func test_desktop_bootstrap_pairing_service_returns_pairing_stopped_when_desktop_stops_mismatch_flow() async {
        let trustedDesktopStore = InMemoryTrustedDesktopStore()
        let bootstrapClient = PollingPairingBootstrapClient(
            claimResponse: PairingClaimResponse(
                schema: PairingProtocol.schema,
                status: .rejected,
                pairingState: .pairingMismatched,
                message: "Pairing mismatch detected.",
                sessionID: "pairing-demo-001",
                desktopDeviceID: nil,
                desktopName: "Studio Mac",
                deviceUUID: "ios-device-001",
                folderID: nil,
                folderPath: nil,
                transport: "lan",
                pairedAt: nil,
                serverNonce: nil
            ),
            stateResponses: [
                PairingClaimResponse(
                    schema: PairingProtocol.schema,
                    status: .rejected,
                    pairingState: .pairingStopped,
                    message: "Desktop canceled this pairing request.",
                    sessionID: "pairing-demo-001",
                    desktopDeviceID: nil,
                    desktopName: "Studio Mac",
                    deviceUUID: "ios-device-001",
                    folderID: nil,
                    folderPath: nil,
                    transport: "lan",
                    pairedAt: nil,
                    serverNonce: nil
                ),
            ]
        )
        let service = DesktopBootstrapPairingService(
            bootstrapClient: bootstrapClient,
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

        XCTAssertEqual(result.phase, .failed)
        XCTAssertEqual(result.backupFlowState, .pairingStopped)
        XCTAssertEqual(result.message, "Desktop canceled this pairing request.")
        XCTAssertNil(trustedDesktop)
    }
}

private struct StaticPairingBootstrapClient: PairingBootstrapClient {
    let response: PairingClaimResponse

    func claimPairing(
        at endpoint: URL,
        request: PairingClaimRequest,
        encryptionTrustKeyBase64: String?
    ) async throws -> PairingClaimResponse {
        _ = encryptionTrustKeyBase64
        XCTAssertEqual(endpoint.absoluteString, PairingQRCodePayload.demo.bootstrapURL.absoluteString)
        XCTAssertEqual(request.sessionID, PairingQRCodePayload.demo.sessionID)
        XCTAssertEqual(request.oneTimePasscode, PairingQRCodePayload.demo.oneTimePasscode)
        XCTAssertEqual(request.deviceUUID, "ios-device-001")
        return response
    }
}

private struct StaticUSBPairingBootstrapClient: PairingUSBBootstrapClient {
    let result: Result<PairingClaimResponse, PairingServiceError>

    func claimPairing(
        using payload: PairingQRCodePayload,
        request: PairingClaimRequest,
        encryptionTrustKeyBase64: String?
    ) async throws -> PairingClaimResponse {
        _ = encryptionTrustKeyBase64
        XCTAssertEqual(payload.sessionID, request.sessionID)
        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}

private actor RetryingPairingBootstrapClient: PairingBootstrapClient {
    private let scriptedResults: [String: Result<PairingClaimResponse, PairingServiceError>]
    private var endpointLog: [String] = []

    init(scriptedResults: [String: Result<PairingClaimResponse, PairingServiceError>]) {
        self.scriptedResults = scriptedResults
    }

    func claimPairing(
        at endpoint: URL,
        request: PairingClaimRequest,
        encryptionTrustKeyBase64: String?
    ) async throws -> PairingClaimResponse {
        _ = encryptionTrustKeyBase64
        endpointLog.append(endpoint.absoluteString)
        XCTAssertEqual(request.deviceUUID, "ios-device-001")
        guard let result = scriptedResults[endpoint.absoluteString] else {
            XCTFail("Unexpected endpoint \(endpoint.absoluteString)")
            throw PairingServiceError.transport(message: "Unexpected endpoint.")
        }

        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }

    func requestedEndpoints() -> [String] {
        endpointLog
    }
}

private actor PollingPairingBootstrapClient: PairingBootstrapClient {
    private let claimResponse: PairingClaimResponse
    private var scriptedStateResponses: [PairingClaimResponse]
    private var observedStateRequestCount = 0

    init(claimResponse: PairingClaimResponse, stateResponses: [PairingClaimResponse]) {
        self.claimResponse = claimResponse
        scriptedStateResponses = stateResponses
    }

    func claimPairing(
        at endpoint: URL,
        request: PairingClaimRequest,
        encryptionTrustKeyBase64: String?
    ) async throws -> PairingClaimResponse {
        _ = encryptionTrustKeyBase64
        XCTAssertEqual(endpoint.absoluteString, PairingQRCodePayload.demo.bootstrapURL.absoluteString)
        XCTAssertEqual(request.deviceUUID, "ios-device-001")
        return claimResponse
    }

    func fetchPairingState(
        at endpoint: URL,
        request: PairingStateRequest,
        encryptionTrustKeyBase64: String?
    ) async throws -> PairingClaimResponse {
        _ = encryptionTrustKeyBase64
        XCTAssertEqual(endpoint.absoluteString, PairingQRCodePayload.demo.bootstrapURL.absoluteString)
        XCTAssertEqual(request.sessionID, "pairing-demo-001")
        XCTAssertEqual(request.deviceUUID, "ios-device-001")
        observedStateRequestCount += 1
        guard !scriptedStateResponses.isEmpty else {
            throw PairingServiceError.transport(message: "Missing scripted pairing state response.")
        }
        return scriptedStateResponses.removeFirst()
    }

    func stateRequestCount() -> Int {
        observedStateRequestCount
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
