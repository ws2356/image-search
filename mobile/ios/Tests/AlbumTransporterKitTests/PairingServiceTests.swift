import Foundation
import XCTest
@testable import AlbumTransporterKit
import Common

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

    func test_url_query_qr_decoder_marks_strict_security_when_sec_is_enabled() {
        let result = URLQueryQRCodePayloadDecoder().decode(
            scannedValue: "https://dl.boldman.net?v=2&ept=127.0.0.1:38933&sid=pairing-demo-001&opt=482913&usp=50211&sec=1"
        )

        guard case .success(let payload) = result else {
            return XCTFail("Expected QR payload to decode successfully.")
        }

        XCTAssertTrue(payload.strictSecurityEnabled)
    }

    func test_desktop_bootstrap_pairing_service_rejects_plaintext_fallback_when_strict_security_is_enabled() async {
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
            capabilityExchangeClient: StaticCapabilityExchangeClient(
                result: .success(
                    CapabilityExchangeResponse(
                        schema: CapabilityExchangeProtocol.schema,
                        status: .accepted,
                        message: "Desktop completed capability exchange.",
                        sessionID: "pairing-demo-001",
                        deviceUUID: "ios-device-001",
                        capabilities: [:]
                    )
                )
            ),
            identityProvider: StaticLocalDeviceIdentityProvider(
                identity: LocalDeviceIdentifier(
                    installID: "install-001",
                    deviceUUID: "ios-device-001",
                    deviceName: "Alice iPhone",
                    platform: "ios"
                )
            ),
            trustedDesktopStore: InMemoryTrustedDesktopStore()
        )
        let payload = PairingQRCodePayload(
            schemaVersion: 2,
            endpointTargets: ["127.0.0.1:38933"],
            sessionID: "pairing-demo-001",
            oneTimePasscode: "482913",
            suggestedUSBPort: 50211,
            strictSecurityEnabled: true
        )

        let result = await service.startPairing(using: payload)

        XCTAssertEqual(
            requirePairingFailure(result),
            .rejected(
                message: "The desktop does not support encrypted transport. Update the desktop app and try again."
            )
        )
    }

    func test_desktop_bootstrap_pairing_service_allows_plaintext_fallback_when_strict_security_is_disabled() async {
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
            capabilityExchangeClient: StaticCapabilityExchangeClient(
                result: .success(
                    CapabilityExchangeResponse(
                        schema: CapabilityExchangeProtocol.schema,
                        status: .accepted,
                        message: "Desktop completed capability exchange.",
                        sessionID: "pairing-demo-001",
                        deviceUUID: "ios-device-001",
                        capabilities: [:]
                    )
                )
            ),
            identityProvider: StaticLocalDeviceIdentityProvider(
                identity: LocalDeviceIdentifier(
                    installID: "install-001",
                    deviceUUID: "ios-device-001",
                    deviceName: "Alice iPhone",
                    platform: "ios"
                )
            ),
            trustedDesktopStore: trustedDesktopStore
        )
        let payload = PairingQRCodePayload(
            schemaVersion: 2,
            endpointTargets: ["127.0.0.1:38933"],
            sessionID: "pairing-demo-001",
            oneTimePasscode: "482913",
            suggestedUSBPort: 50211,
            strictSecurityEnabled: false
        )

        let result = await service.startPairing(using: payload)
        let response = requirePairingSuccess(result)
        let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop()

        XCTAssertEqual(response.sessionID, "pairing-demo-001")
        XCTAssertFalse(trustedDesktop?.encryptionEnabled ?? true)
        XCTAssertFalse(trustedDesktop?.strictSecurityEnabled ?? true)
    }

    func test_desktop_bootstrap_pairing_service_persists_encryption_support_after_pairing() async {
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
            capabilityExchangeClient: StaticCapabilityExchangeClient(
                result: .success(
                    CapabilityExchangeResponse(
                        schema: CapabilityExchangeProtocol.schema,
                        status: .accepted,
                        message: "Desktop completed capability exchange.",
                        sessionID: "pairing-demo-001",
                        deviceUUID: "ios-device-001",
                        capabilities: ["encryption": 1]
                    )
                )
            ),
            identityProvider: StaticLocalDeviceIdentityProvider(
                identity: LocalDeviceIdentifier(
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

        XCTAssertEqual(requirePairingSuccess(result).sessionID, "pairing-demo-001")
        XCTAssertTrue(trustedDesktop?.encryptionEnabled ?? false)
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
                identity: LocalDeviceIdentifier(
                    installID: "install-001",
                    deviceUUID: "ios-device-001",
                    deviceName: "Alice iPhone",
                    platform: "ios"
                )
            ),
            trustedDesktopStore: trustedDesktopStore
        )

        let result = await service.startPairing(using: .demo)
        let response = requirePairingSuccess(result)
        let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop()

        XCTAssertEqual(response.desktopName, "Studio Mac")
        XCTAssertEqual(response.sessionID, "pairing-demo-001")
        XCTAssertEqual(response.transport, .lan)
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
                identity: LocalDeviceIdentifier(
                    installID: "install-001",
                    deviceUUID: "ios-device-001",
                    deviceName: "Alice iPhone",
                    platform: "ios"
                )
            ),
            trustedDesktopStore: InMemoryTrustedDesktopStore()
        )

        let result = await service.startPairing(using: .demo)
        let error = requirePairingFailure(result)

        XCTAssertEqual(error, .expired(message: "This QR code expired on desktop. Refresh and scan again."))
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
                identity: LocalDeviceIdentifier(
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
        let response = requirePairingSuccess(result)
        let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop()
        let requestedEndpoints = await bootstrapClient.requestedEndpoints()

        XCTAssertEqual(response.sessionID, "pairing-demo-001")
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
                identity: LocalDeviceIdentifier(
                    installID: "install-001",
                    deviceUUID: "ios-device-001",
                    deviceName: "Alice iPhone",
                    platform: "ios"
                )
            ),
            trustedDesktopStore: trustedDesktopStore
        )

        let result = await service.startPairing(using: .demo)
        let response = requirePairingSuccess(result)
        let lanRequestedEndpoints = await lanClient.requestedEndpoints()
        let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop()

        XCTAssertEqual(response.transport, .usb)
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
                identity: LocalDeviceIdentifier(
                    installID: "install-001",
                    deviceUUID: "ios-device-001",
                    deviceName: "Alice iPhone",
                    platform: "ios"
                )
            ),
            trustedDesktopStore: trustedDesktopStore
        )

        let result = await service.startPairing(using: .demo)
        let response = requirePairingSuccess(result)
        let lanRequestedEndpoints = await lanClient.requestedEndpoints()
        let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop()

        XCTAssertEqual(response.transport, .lan)
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
                identity: LocalDeviceIdentifier(
                    installID: "install-001",
                    deviceUUID: "ios-device-001",
                    deviceName: "Alice iPhone",
                    platform: "ios"
                )
            ),
            trustedDesktopStore: trustedDesktopStore
        )

        let result = await service.startPairing(using: .demo)
        let response = requirePairingSuccess(result)
        let stateRequestCount = await bootstrapClient.stateRequestCount()
        let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop()

        XCTAssertEqual(response.sessionID, "pairing-demo-001")
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
                identity: LocalDeviceIdentifier(
                    installID: "install-001",
                    deviceUUID: "ios-device-001",
                    deviceName: "Alice iPhone",
                    platform: "ios"
                )
            ),
            trustedDesktopStore: trustedDesktopStore
        )

        let result = await service.startPairing(using: .demo)
        let error = requirePairingFailure(result)
        let trustedDesktop = await trustedDesktopStore.loadTrustedDesktop()

        XCTAssertEqual(error, .rejected(message: "Desktop canceled this pairing request."))
        XCTAssertNil(trustedDesktop)
    }
}

private func requirePairingSuccess(
    _ result: Result<PairingResponse, PairingError>,
    file: StaticString = #filePath,
    line: UInt = #line
) -> PairingResponse {
    switch result {
    case .success(let response):
        return response
    case .failure(let error):
        XCTFail("Expected pairing success, got \(error)", file: file, line: line)
        return PairingResponse(sessionID: "", desktopName: "", transport: .lan)
    }
}

private func requirePairingFailure(
    _ result: Result<PairingResponse, PairingError>,
    file: StaticString = #filePath,
    line: UInt = #line
) -> PairingError {
    switch result {
    case .success(let response):
        XCTFail("Expected pairing failure, got success \(response)", file: file, line: line)
        return .transport(message: "")
    case .failure(let error):
        return error
    }
}

private struct StaticPairingBootstrapClient: PairingBootstrapClient {
    let response: PairingClaimResponse

    func claimPairing(
        at endpoint: URL,
        request: PairingClaimRequest
    ) async throws -> PairingClaimResponse {
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
        request: PairingClaimRequest
    ) async throws -> PairingClaimResponse {
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
        request: PairingClaimRequest
    ) async throws -> PairingClaimResponse {
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
        request: PairingClaimRequest
    ) async throws -> PairingClaimResponse {
        XCTAssertEqual(endpoint.absoluteString, PairingQRCodePayload.demo.bootstrapURL.absoluteString)
        XCTAssertEqual(request.deviceUUID, "ios-device-001")
        return claimResponse
    }

    func fetchPairingState(
        at endpoint: URL,
        request: PairingStateRequest
    ) async throws -> PairingClaimResponse {
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

private struct StaticCapabilityExchangeClient: MobileCapabilityExchangeClient {
    let result: Result<CapabilityExchangeResponse, TransferClientError>

    func exchangeCapabilities(
        _ mobileCapabilities: [String: Int],
        desktop: TrustedDesktopRecord
    ) async throws -> CapabilityExchangeResponse {
        XCTAssertEqual(mobileCapabilities["encryption"], 1)
        XCTAssertEqual(desktop.lastSessionID, "pairing-demo-001")
        switch result {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        }
    }
}

private struct StaticLocalDeviceIdentityProvider: LocalDeviceIdentifierProviding {
    let identity: LocalDeviceIdentifier

    func currentIdentifier() async -> LocalDeviceIdentifier {
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
