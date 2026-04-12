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
        model.scannedQRCodeValue = PairingQRCodePayload.demoScanValue
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
        model.scannedQRCodeValue = PairingQRCodePayload.demoScanValue
        await model.beginPairing()
        await model.startBackup()
        model.requestStopTransfer()
        await model.confirmStopTransfer()

        XCTAssertEqual(model.route, .interrupted)
        XCTAssertEqual(model.interruptionReason, .stoppedByUser)
        XCTAssertEqual(model.homeSummary.primaryAction, .resumeBackup)
    }

    func test_start_backup_polls_transfer_progress_while_session_is_running() async {
        let inFlightSnapshot = TransferSnapshot(
            transferredCount: 2,
            totalCount: 5,
            failedCount: 0,
            transport: .lan,
            etaDescription: nil,
            statusMessage: "Processed 2 of 5 items for the paired desktop.",
            guidanceMessage: "Keep the app in the foreground while the phone sends items to the desktop.",
            isIncompleteLibrary: false
        )
        let finalSnapshot = TransferSnapshot(
            transferredCount: 5,
            totalCount: 5,
            failedCount: 0,
            transport: .lan,
            etaDescription: nil,
            statusMessage: "Phone finished sending the current batch of media to the paired desktop.",
            guidanceMessage: "Tap Finish Backup after the desktop confirms the transfer session is complete.",
            isIncompleteLibrary: false
        )
        let model = MobileAppModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: PollingTransferService(
                inFlightSnapshot: inFlightSnapshot,
                finalSnapshot: finalSnapshot
            ),
            telemetryClient: RecordingTelemetryClient(),
            transferProgressPollingInterval: .milliseconds(10)
        )

        await model.load()
        await model.openScanFlow()
        model.scannedQRCodeValue = PairingQRCodePayload.demoScanValue
        await model.beginPairing()

        let transferTask = Task {
            await model.startBackup()
        }
        try? await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(model.route, .transfer)
        XCTAssertEqual(model.transferSnapshot.totalCount, 5)
        XCTAssertEqual(model.transferSnapshot.transferredCount, 2)

        await transferTask.value
        XCTAssertEqual(model.transferSnapshot.transferredCount, 5)
    }

    func test_qr_payload_decoder_uses_url_query_format() {
        let decoder = URLQueryQRCodePayloadDecoder()
        let result = decoder.decode(scannedValue: "https://dl.boldman.net?v=1&ept=desktop.local:38933,192.168.50.17:38933&sid=pairing-demo-123&opt=482913")

        guard case .success(let decoded) = result else {
            return XCTFail("Expected successful payload decoding")
        }

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.endpointTargets, ["desktop.local:38933", "192.168.50.17:38933"])
        XCTAssertEqual(decoded.sessionID, "pairing-demo-123")
        XCTAssertEqual(decoded.oneTimePasscode, "482913")
        XCTAssertEqual(
            decoded.bootstrapURLs.map(\.absoluteString),
            [
                "http://desktop.local:38933/api/mobile/pairing/claim",
                "http://192.168.50.17:38933/api/mobile/pairing/claim",
            ]
        )
    }
}

private struct StaticPairingService: PairingService {
    func startPairing(using payload: PairingQRCodePayload) async -> PairingStatus {
        PairingStatus(
            phase: .paired,
            desktopName: "Studio Mac",
            sessionID: payload.sessionID,
            transport: .lan,
            message: "Pairing succeeded for \(payload.sessionID)."
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
    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        progress(.demo)
        return .demo
    }

    func stopTransfer(current: TransferSnapshot) async -> InterruptionReason {
        .stoppedByUser
    }

    func resumeTransfer(from snapshot: TransferSnapshot, progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        progress(snapshot)
        return snapshot
    }

    func completeTransfer(current: TransferSnapshot) async -> TransferSnapshot {
        current
    }

    func progressSnapshot() async -> TransferSnapshot? {
        .demo
    }
}

private actor RecordingTelemetryClient: TelemetryClient {
    func record(event: MobileTelemetryEvent) async {}
}

private actor PollingTransferService: TransferService {
    private let inFlightSnapshot: TransferSnapshot
    private let finalSnapshot: TransferSnapshot
    private var currentSnapshotValue: TransferSnapshot?

    init(inFlightSnapshot: TransferSnapshot, finalSnapshot: TransferSnapshot) {
        self.inFlightSnapshot = inFlightSnapshot
        self.finalSnapshot = finalSnapshot
    }

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        currentSnapshotValue = inFlightSnapshot
        try? await Task.sleep(for: .milliseconds(80))
        currentSnapshotValue = finalSnapshot
        return finalSnapshot
    }

    func stopTransfer(current: TransferSnapshot) async -> InterruptionReason {
        .stoppedByUser
    }

    func resumeTransfer(from snapshot: TransferSnapshot, progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        currentSnapshotValue = snapshot
        return snapshot
    }

    func completeTransfer(current: TransferSnapshot) async -> TransferSnapshot {
        current
    }

    func progressSnapshot() async -> TransferSnapshot? {
        currentSnapshotValue
    }
}
