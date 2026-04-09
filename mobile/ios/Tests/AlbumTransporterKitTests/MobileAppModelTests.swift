import XCTest
@testable import AlbumTransporterKit

@MainActor
final class MobileAppModelTests: XCTestCase {
    func test_load_routes_to_home_for_first_launch() async {
        let store = InMemoryAppStateStore(snapshot: .firstLaunch)
        let model = MobileAppModel(
            stateStore: store,
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .demo),
            transferService: StaticTransferService(),
            telemetryClient: RecordingTelemetryClient()
        )

        await model.load()

        XCTAssertEqual(model.route, .home)
        XCTAssertEqual(model.homeSummary.primaryAction, .scanDesktopQRCode)
    }

    func test_start_backup_shows_low_battery_alert_when_needed() async {
        let model = MobileAppModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .demo),
            transferService: StaticTransferService(),
            telemetryClient: RecordingTelemetryClient()
        )

        await model.load()
        await model.openScanFlow()
        await model.beginPairing()
        await model.startBackup()

        XCTAssertEqual(model.route, .permissions)
        XCTAssertTrue(model.isShowingLowBatteryWarning)
    }

    func test_stop_transfer_moves_to_resumable_state() async {
        let model = MobileAppModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: StaticTransferService(),
            telemetryClient: RecordingTelemetryClient()
        )

        await model.load()
        await model.openScanFlow()
        await model.beginPairing()
        await model.startBackup()
        model.requestStopTransfer()
        await model.confirmStopTransfer()

        XCTAssertEqual(model.route, .interrupted)
        XCTAssertEqual(model.interruptionReason, .stoppedByUser)
        XCTAssertEqual(model.homeSummary.primaryAction, .resumeBackup)
    }

    func test_qr_payload_decoder_uses_url_query_format() {
        let decoder = URLQueryQRCodePayloadDecoder()
        let result = decoder.decode(scannedValue: "https://dl.boldman.net?v=1&endpoint=https%3A%2F%2Fdesktop.local%2Fbootstrap&pairing_id=pairing-demo-123&secret=bootstrap-secret")

        guard case .success(let decoded) = result else {
            return XCTFail("Expected successful payload decoding")
        }

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.pairingID, "pairing-demo-123")
        XCTAssertEqual(decoded.bootstrapURL.absoluteString, "https://desktop.local/bootstrap")
    }
}

private struct StaticPairingService: PairingService {
    func startPairing(using payload: PairingQRCodePayload) async -> PairingStatus {
        PairingStatus(
            phase: .paired,
            desktopName: "Studio Mac",
            message: "Pairing succeeded for \(payload.pairingID)."
        )
    }
}

private struct StaticQRCodePayloadDecoder: QRCodePayloadDecoding {
    func decode(scannedValue: String) -> Result<PairingQRCodePayload, QRCodePayloadDecoderError> {
        .success(.demo)
    }
}

private struct StaticPermissionService: PermissionService {
    let summary: PermissionSummary

    func loadPermissionSummary() async -> PermissionSummary {
        summary
    }
}

private struct StaticTransferService: TransferService {
    func startTransfer() async -> TransferSnapshot {
        .demo
    }

    func stopTransfer(current: TransferSnapshot) async -> InterruptionReason {
        .stoppedByUser
    }

    func resumeTransfer(from snapshot: TransferSnapshot) async -> TransferSnapshot {
        snapshot
    }

    func completeTransfer(current: TransferSnapshot) async -> TransferSnapshot {
        current
    }
}

private actor RecordingTelemetryClient: TelemetryClient {
    func record(event: MobileTelemetryEvent) async {}
}
