import Foundation
import XCTest
@testable import AlbumTransporterKit

final class USBTransportServicesTests: XCTestCase {
    func test_build_desktop_usb_auth_digest_matches_sha256_material() {
        let digest = buildDesktopUSBAuthDigest(
            oneTimePasscode: "482913",
            rand: "rand-001"
        )

        XCTAssertEqual(
            digest,
            "4d0e4431843a8a654a39e4eaba0f2dc841ddd9407984ec86db4806c0e60ed0ce"
        )
    }

    func test_adaptive_mobile_transfer_client_prefers_usb_for_usb_transport() async throws {
        let lanClient = RecordingTransferClient()
        let usbClient = RecordingTransferClient()
        let adaptiveClient = AdaptiveMobileTransferClient(
            lanClient: lanClient,
            usbClient: usbClient
        )
        let desktop = trustedDesktop(transport: .usb)

        try await adaptiveClient.startSession(desktop: desktop, totalAssets: 3)

        let lanStartCalls = await lanClient.startCalls()
        let usbStartCalls = await usbClient.startCalls()
        XCTAssertEqual(usbStartCalls, 1)
        XCTAssertEqual(lanStartCalls, 0)
    }

    func test_adaptive_mobile_transfer_client_falls_back_to_lan_when_usb_throws() async throws {
        let lanClient = RecordingTransferClient()
        let usbClient = RecordingTransferClient(
            startSessionError: TransferClientError.transport(message: "USB disconnected")
        )
        let adaptiveClient = AdaptiveMobileTransferClient(
            lanClient: lanClient,
            usbClient: usbClient
        )
        let desktop = trustedDesktop(transport: .usb)

        try await adaptiveClient.startSession(desktop: desktop, totalAssets: 5)

        let lanStartCalls = await lanClient.startCalls()
        let usbStartCalls = await usbClient.startCalls()
        XCTAssertEqual(usbStartCalls, 1)
        XCTAssertEqual(lanStartCalls, 1)
    }

    func test_adaptive_mobile_transfer_client_uses_lan_for_lan_transport() async throws {
        let lanClient = RecordingTransferClient()
        let usbClient = RecordingTransferClient()
        let adaptiveClient = AdaptiveMobileTransferClient(
            lanClient: lanClient,
            usbClient: usbClient
        )
        let desktop = trustedDesktop(transport: .lan)

        try await adaptiveClient.startSession(desktop: desktop, totalAssets: 1)

        let lanStartCalls = await lanClient.startCalls()
        let usbStartCalls = await usbClient.startCalls()
        XCTAssertEqual(lanStartCalls, 1)
        XCTAssertEqual(usbStartCalls, 0)
    }

    private func trustedDesktop(transport: TransferTransport) -> TrustedDesktopRecord {
        TrustedDesktopRecord(
            desktopDeviceID: "desktop-device-001",
            desktopName: "Studio Mac",
            endpointURL: URL(string: "http://127.0.0.1:38933/api/mobile/pairing/claim")!,
            mobileDeviceUUID: "ios-device-001",
            sharedKeyBase64: "shared-key-001",
            transport: transport,
            lastSessionID: "pairing-demo-001",
            pairedAt: Date(timeIntervalSince1970: 1_776_123_610)
        )
    }
}

private actor RecordingTransferClient: MobileTransferClient {
    private let startSessionError: Error?
    private var startCallCount = 0

    init(startSessionError: Error? = nil) {
        self.startSessionError = startSessionError
    }

    func startSession(desktop: TrustedDesktopRecord, totalAssets: Int) async throws {
        startCallCount += 1
        if let startSessionError {
            throw startSessionError
        }
    }

    func lookupExistingAssets(
        _ candidates: [TransferAssetExistenceCandidate],
        desktop: TrustedDesktopRecord
    ) async throws -> [String: TransferAssetExistenceMatch] {
        [:]
    }

    func uploadAsset(_ asset: ExportedTransferAsset, desktop: TrustedDesktopRecord) async throws -> TransferServerResponse {
        TransferServerResponse(
            schema: TransferProtocol.schema,
            status: .stored,
            message: "stored",
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            totalAssets: nil,
            localRelativePath: "2026-04/\(asset.descriptor.filename)"
        )
    }

    func completeSession(desktop: TrustedDesktopRecord, transferredCount: Int, failedCount: Int) async throws -> TransferServerResponse {
        TransferServerResponse(
            schema: TransferProtocol.schema,
            status: .completed,
            message: "completed",
            sessionID: desktop.lastSessionID,
            deviceUUID: desktop.mobileDeviceUUID,
            totalAssets: nil,
            localRelativePath: nil
        )
    }

    func startCalls() -> Int {
        startCallCount
    }
}
