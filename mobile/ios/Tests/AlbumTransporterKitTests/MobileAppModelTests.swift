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

    func test_load_does_not_trigger_transfer_recovery_while_idle() async {
        let transferService = ForegroundRecoveryTrackingTransferService()
        let model = MobileAppModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .demo),
            transferService: transferService,
            telemetryClient: RecordingTelemetryClient()
        )

        await model.load()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let recoveryCallCount = await transferService.foregroundRecoveryCallCount()
        XCTAssertEqual(recoveryCallCount, 0)
    }

    func test_start_backup_shows_low_battery_alert_when_needed() async {
        let lowBatteryFullAccess = PermissionSummary(
            cameraGranted: true,
            notificationsGranted: true,
            mediaScope: .full,
            excludedCategoryDescription: nil,
            lowBatteryWarningNeeded: true,
            isCharging: false
        )
        let model = MobileAppModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: lowBatteryFullAccess),
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

    func test_begin_pairing_returns_home_when_desktop_stops_pairing() async {
        let model = MobileAppModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StoppedPairingService(),
            permissionService: StaticPermissionService(summary: .demo),
            transferService: StaticTransferService(),
            telemetryClient: RecordingTelemetryClient()
        )

        await model.load()
        await model.openScanFlow()
        model.scannedQRCodeValue = PairingQRCodePayload.demoScanValue
        await model.beginPairing()

        XCTAssertEqual(model.route, .home)
        XCTAssertEqual(model.homeSummary.primaryAction, .scanDesktopQRCode)
    }

    func test_start_backup_shows_full_media_access_reminder_before_continuing() async {
        let limitedAccessSummary = PermissionSummary(
            cameraGranted: true,
            notificationsGranted: true,
            mediaScope: .limited,
            excludedCategoryDescription: "Only selected items are currently granted by iOS.",
            lowBatteryWarningNeeded: false,
            isCharging: true
        )
        let model = MobileAppModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: limitedAccessSummary),
            transferService: StaticTransferService(),
            telemetryClient: RecordingTelemetryClient()
        )

        await model.load()
        await model.openScanFlow()
        model.scannedQRCodeValue = PairingQRCodePayload.demoScanValue
        await model.beginPairing()
        await model.startBackup()

        XCTAssertEqual(model.route, .permissions)
        XCTAssertTrue(model.isShowingMediaAccessAlert)
        XCTAssertFalse(model.mediaAccessAlertMessage.isEmpty)

        await model.continueBackupWithCurrentMediaAccess()
        XCTAssertTrue(model.isShowingRemoveAfterBackupPrompt)
        await model.selectRemoveAfterBackupPreferenceAndContinue(false)
        XCTAssertEqual(model.route, .completed)
    }

    func test_low_battery_not_now_returns_home_and_reports_stopped_transfer() async {
        let lowBatteryFullAccess = PermissionSummary(
            cameraGranted: true,
            notificationsGranted: false,
            mediaScope: .full,
            excludedCategoryDescription: nil,
            lowBatteryWarningNeeded: true,
            isCharging: false
        )
        let transferService = StopTrackingTransferService()
        let model = MobileAppModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: lowBatteryFullAccess),
            transferService: transferService,
            telemetryClient: RecordingTelemetryClient()
        )

        await model.load()
        await model.openScanFlow()
        model.scannedQRCodeValue = PairingQRCodePayload.demoScanValue
        await model.beginPairing()
        await model.startBackup()
        XCTAssertTrue(model.isShowingLowBatteryWarning)

        await model.cancelBackupFromLowBatteryWarning()

        XCTAssertEqual(model.route, .home)
        XCTAssertEqual(model.homeSummary.primaryAction, .scanDesktopQRCode)
        let stopCallCount = await transferService.stopCallCount()
        XCTAssertEqual(stopCallCount, 1)
    }

    func test_stop_transfer_returns_home_without_interrupted_page() async {
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
            guidanceMessage: "Backup completes automatically after the desktop confirms this transfer session.",
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
            transferProgressPollingIntervalNanoseconds: 10_000_000
        )

        await model.load()
        await model.openScanFlow()
        model.scannedQRCodeValue = PairingQRCodePayload.demoScanValue
        await model.beginPairing()

        let transferTask = Task {
            await model.startBackup()
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        model.requestStopTransfer()
        await model.confirmStopTransfer()

        XCTAssertEqual(model.route, .home)
        XCTAssertEqual(model.homeSummary.primaryAction, .scanDesktopQRCode)
        XCTAssertFalse(model.isShowingStopConfirmation)
        XCTAssertNotNil(model.homeSummary.lastBackupDescription)
        XCTAssertNotNil(model.homeSummary.previouslyTransferredDescription)

        await transferTask.value
        XCTAssertEqual(model.route, .home)
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
            guidanceMessage: "Backup completes automatically after the desktop confirms this transfer session.",
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
            transferProgressPollingIntervalNanoseconds: 10_000_000
        )

        await model.load()
        await model.openScanFlow()
        model.scannedQRCodeValue = PairingQRCodePayload.demoScanValue
        await model.beginPairing()

        let transferTask = Task {
            await model.startBackup()
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertTrue(model.isShowingRemoveAfterBackupPrompt)
        await model.selectRemoveAfterBackupPreferenceAndContinue(false)
        try? await Task.sleep(nanoseconds: 30_000_000)

        XCTAssertTrue(model.route == .transfer || model.route == .completed)
        XCTAssertEqual(model.transferSnapshot.totalCount, 5)
        XCTAssertGreaterThanOrEqual(model.transferSnapshot.transferredCount, 2)

        await transferTask.value
        XCTAssertEqual(model.route, .completed)
        XCTAssertEqual(model.transferSnapshot.transferredCount, 5)
        XCTAssertEqual(model.completionSummary.itemsBackedUp, 5)
        XCTAssertEqual(model.completionSummary.totalTransferredDescription, "5/5")
        XCTAssertNotNil(model.completionSummary.durationDescription)
        XCTAssertNotNil(model.completionSummary.completedAtDescription)
    }

    func test_qr_payload_decoder_uses_url_query_format() {
        let decoder = URLQueryQRCodePayloadDecoder()
        let result = decoder.decode(scannedValue: "https://dl.boldman.net?v=2&ept=desktop.local:38933,192.168.50.17:38933&sid=pairing-demo-123&opt=482913&usp=50211")

        guard case .success(let decoded) = result else {
            return XCTFail("Expected successful payload decoding")
        }

        XCTAssertEqual(decoded.schemaVersion, 2)
        XCTAssertEqual(decoded.endpointTargets, ["desktop.local:38933", "192.168.50.17:38933"])
        XCTAssertEqual(decoded.sessionID, "pairing-demo-123")
        XCTAssertEqual(decoded.oneTimePasscode, "482913")
        XCTAssertEqual(decoded.suggestedUSBPort, 50211)
        XCTAssertEqual(
            decoded.bootstrapURLs.map(\.absoluteString),
            [
                "http://desktop.local:38933/api/mobile/pairing/claim",
                "http://192.168.50.17:38933/api/mobile/pairing/claim",
            ]
        )
    }

    func test_qr_payload_decoder_keeps_v1_backward_compatibility() {
        let decoder = URLQueryQRCodePayloadDecoder()
        let result = decoder.decode(
            scannedValue: "https://dl.boldman.net?v=1&ept=desktop.local:38933&sid=pairing-demo-legacy&opt=123456"
        )

        guard case .success(let decoded) = result else {
            return XCTFail("Expected successful payload decoding for v1 payload")
        }

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.endpointTargets, ["desktop.local:38933"])
        XCTAssertEqual(decoded.sessionID, "pairing-demo-legacy")
        XCTAssertEqual(decoded.oneTimePasscode, "123456")
        XCTAssertNil(decoded.suggestedUSBPort)
    }

    func test_handle_incoming_universal_link_routes_to_permissions_after_pairing() async {
        let model = MobileAppModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: URLQueryQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: StaticTransferService(),
            telemetryClient: RecordingTelemetryClient()
        )

        await model.load()
        await model.handleIncomingUniversalLink(URL(string: PairingQRCodePayload.demoScanValue)!)

        XCTAssertEqual(model.route, .permissions)
        XCTAssertEqual(model.pairingStatus.phase, .paired)
        XCTAssertEqual(model.scannedQRCodeValue, PairingQRCodePayload.demoScanValue)
    }

    func test_handle_incoming_universal_link_with_invalid_payload_shows_pairing_failure() async {
        let model = MobileAppModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: URLQueryQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: StaticTransferService(),
            telemetryClient: RecordingTelemetryClient()
        )

        await model.load()
        await model.handleIncomingUniversalLink(URL(string: "https://dl.boldman.net?sid=missing-fields")!)

        XCTAssertEqual(model.route, .scanAndPair)
        XCTAssertEqual(model.pairingStatus.phase, .failed)
        XCTAssertTrue(model.pairingStatus.message.contains("missing the required field"))
    }

    func test_handle_incoming_universal_link_prompts_before_replacing_active_transfer() async {
        let inFlightSnapshot = TransferSnapshot(
            transferredCount: 1,
            totalCount: 5,
            failedCount: 0,
            transport: .lan,
            etaDescription: nil,
            statusMessage: "Sending items to desktop.",
            guidanceMessage: "Keep app in foreground.",
            isIncompleteLibrary: false
        )
        let finalSnapshot = TransferSnapshot(
            transferredCount: 5,
            totalCount: 5,
            failedCount: 0,
            transport: .lan,
            etaDescription: nil,
            statusMessage: "Completed transfer.",
            guidanceMessage: "Done.",
            isIncompleteLibrary: false
        )
        let transferService = DelayedTransferService(
            inFlightSnapshot: inFlightSnapshot,
            finalSnapshot: finalSnapshot,
            transferDurationNanoseconds: 500_000_000
        )
        let model = MobileAppModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: URLQueryQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: transferService,
            telemetryClient: RecordingTelemetryClient(),
            transferProgressPollingIntervalNanoseconds: 10_000_000
        )

        await model.load()
        await model.openScanFlow()
        model.scannedQRCodeValue = PairingQRCodePayload.demoScanValue
        await model.beginPairing()
        await model.startBackup()
        let transferTask = Task {
            await model.selectRemoveAfterBackupPreferenceAndContinue(false)
        }
        try? await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertEqual(model.route, .transfer)

        await model.handleIncomingUniversalLink(URL(string: PairingQRCodePayload.demoScanValue)!)

        XCTAssertTrue(model.isShowingIncomingLinkReplacementConfirmation)
        model.cancelIncomingUniversalLinkReplacement()
        XCTAssertFalse(model.isShowingIncomingLinkReplacementConfirmation)
        XCTAssertEqual(model.route, .transfer)

        await transferTask.value
    }

    func test_confirm_incoming_universal_link_replacement_stops_transfer_and_starts_new_pairing() async {
        let inFlightSnapshot = TransferSnapshot(
            transferredCount: 1,
            totalCount: 5,
            failedCount: 0,
            transport: .lan,
            etaDescription: nil,
            statusMessage: "Sending items to desktop.",
            guidanceMessage: "Keep app in foreground.",
            isIncompleteLibrary: false
        )
        let finalSnapshot = TransferSnapshot(
            transferredCount: 5,
            totalCount: 5,
            failedCount: 0,
            transport: .lan,
            etaDescription: nil,
            statusMessage: "Completed transfer.",
            guidanceMessage: "Done.",
            isIncompleteLibrary: false
        )
        let transferService = DelayedTransferService(
            inFlightSnapshot: inFlightSnapshot,
            finalSnapshot: finalSnapshot,
            transferDurationNanoseconds: 500_000_000
        )
        let model = MobileAppModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: URLQueryQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: transferService,
            telemetryClient: RecordingTelemetryClient(),
            transferProgressPollingIntervalNanoseconds: 10_000_000
        )

        await model.load()
        await model.openScanFlow()
        model.scannedQRCodeValue = PairingQRCodePayload.demoScanValue
        await model.beginPairing()
        await model.startBackup()
        let transferTask = Task {
            await model.selectRemoveAfterBackupPreferenceAndContinue(false)
        }
        try? await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertEqual(model.route, .transfer)

        let replacementLink = "https://dl.boldman.net?v=2&ept=desktop.local:38933&sid=pairing-replacement-001&opt=456123&usp=50211"
        await model.handleIncomingUniversalLink(URL(string: replacementLink)!)
        XCTAssertTrue(model.isShowingIncomingLinkReplacementConfirmation)

        await model.confirmIncomingUniversalLinkReplacement()

        XCTAssertFalse(model.isShowingIncomingLinkReplacementConfirmation)
        XCTAssertEqual(model.route, .permissions)
        XCTAssertEqual(model.pairingStatus.phase, .paired)
        XCTAssertEqual(model.scannedQRCodeValue, replacementLink)
        let stopCallCount = await transferService.stopCallCount()
        XCTAssertEqual(stopCallCount, 1)

        await transferTask.value
    }

    func test_open_scan_flow_returns_without_waiting_for_slow_side_effect_io() async {
        let model = MobileAppModel(
            stateStore: SlowAppStateStore(saveDelay: .milliseconds(600)),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .demo),
            transferService: StaticTransferService(),
            telemetryClient: SlowTelemetryClient(recordDelay: .milliseconds(600))
        )
        let clock = ContinuousClock()
        let start = clock.now

        await model.openScanFlow()

        let elapsed = start.duration(to: clock.now)
        XCTAssertEqual(model.route, .scanAndPair)
        XCTAssertLessThan(elapsed, .milliseconds(250))
    }

    func test_handle_app_did_become_active_does_not_trigger_transfer_recovery_while_idle() async {
        let transferService = ForegroundRecoveryTrackingTransferService()
        let model = MobileAppModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .demo),
            transferService: transferService,
            telemetryClient: RecordingTelemetryClient()
        )

        await model.handleAppDidBecomeActive()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let recoveryCallCount = await transferService.foregroundRecoveryCallCount()
        XCTAssertEqual(recoveryCallCount, 0)
    }

    func test_complete_transfer_moves_assets_to_recently_removed_when_enabled() async {
        let completedSnapshot = TransferSnapshot(
            transferredCount: 3,
            totalCount: 3,
            failedCount: 0,
            transport: .lan,
            etaDescription: nil,
            statusMessage: "Phone finished sending the current batch of media to the paired desktop.",
            guidanceMessage: "Backup completes automatically after the desktop confirms this transfer session.",
            isIncompleteLibrary: false
        )
        let transferService = CleanupTrackingTransferService(completedSnapshot: completedSnapshot)
        let model = MobileAppModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: transferService,
            telemetryClient: RecordingTelemetryClient()
        )

        await model.load()
        model.setRemoveAfterBackupEnabled(true)
        await model.openScanFlow()
        model.scannedQRCodeValue = PairingQRCodePayload.demoScanValue
        await model.beginPairing()
        await model.startBackup()
        XCTAssertTrue(model.isShowingRemoveAfterBackupPrompt)
        await model.selectRemoveAfterBackupPreferenceAndContinue(true)

        let cleanupCallCount = await transferService.cleanupCallCount()
        XCTAssertEqual(cleanupCallCount, 1)
        XCTAssertTrue(model.completionSummary.message.contains("Moved 3 transferred items to Recently Removed"))
    }

    func test_begin_pairing_records_invalid_qr_failure_reason() async {
        let telemetryClient = RecordingTelemetryClient()
        let model = MobileAppModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: FailingQRCodePayloadDecoder(error: .invalidURL),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .demo),
            transferService: StaticTransferService(),
            telemetryClient: telemetryClient
        )

        await model.load()
        await model.openScanFlow()
        model.scannedQRCodeValue = "not-a-valid-payload"
        await model.beginPairing()
        try? await Task.sleep(nanoseconds: 50_000_000)

        let failureRecord = await telemetryClient.latestRecord(for: .pairingFailed)
        XCTAssertEqual(
            failureRecord?.attributes["pairing.failure_reason"],
            .string("invalid_qr_payload")
        )
        XCTAssertEqual(
            failureRecord?.attributes["pairing.failure_message"],
            .string(QRCodePayloadDecoderError.invalidURL.message)
        )
        XCTAssertEqual(
            failureRecord?.attributes["app.route"],
            .string(AppRoute.scanAndPair.rawValue)
        )
    }

    func test_start_backup_records_preflight_and_completion_telemetry_context() async {
        let completedSnapshot = TransferSnapshot(
            transferredCount: 3,
            totalCount: 3,
            failedCount: 0,
            transport: .lan,
            etaDescription: nil,
            statusMessage: "Phone finished sending the current batch of media to the paired desktop.",
            guidanceMessage: "Backup completes automatically after the desktop confirms this transfer session.",
            isIncompleteLibrary: false
        )
        let telemetryClient = RecordingTelemetryClient()
        let transferService = CleanupTrackingTransferService(completedSnapshot: completedSnapshot)
        let model = MobileAppModel(
            stateStore: InMemoryAppStateStore(snapshot: .firstLaunch),
            qrCodePayloadDecoder: StaticQRCodePayloadDecoder(),
            pairingService: StaticPairingService(),
            permissionService: StaticPermissionService(summary: .allClear),
            transferService: transferService,
            telemetryClient: telemetryClient
        )

        await model.load()
        await model.openScanFlow()
        model.scannedQRCodeValue = PairingQRCodePayload.demoScanValue
        await model.beginPairing()
        await model.startBackup()
        await model.selectRemoveAfterBackupPreferenceAndContinue(true)
        try? await Task.sleep(nanoseconds: 50_000_000)

        let preflightRecord = await telemetryClient.latestRecord(for: .backupPreflightStarted)
        XCTAssertEqual(
            preflightRecord?.attributes["permission.media_scope"],
            .string(PermissionScope.full.rawValue)
        )
        XCTAssertEqual(
            preflightRecord?.attributes["app.route"],
            .string(AppRoute.permissions.rawValue)
        )

        let completionRecord = await telemetryClient.latestRecord(for: .transferCompleted)
        XCTAssertEqual(
            completionRecord?.attributes["transfer.cleanup_result"],
            .string("removed")
        )
        XCTAssertEqual(
            completionRecord?.attributes["transfer.cleanup_removed_count"],
            .int(3)
        )
        XCTAssertEqual(
            completionRecord?.attributes["transfer.total_count"],
            .int(3)
        )
        XCTAssertEqual(
            completionRecord?.attributes["transfer.transport"],
            .string(TransferTransport.lan.rawValue)
        )
        XCTAssertEqual(
            completionRecord?.attributes["backup.remove_after_backup_enabled"],
            .bool(true)
        )
    }
}

private struct StaticPairingService: PairingService {
    func startPairing(using payload: PairingQRCodePayload) async -> PairingStatus {
        PairingStatus(
            phase: .paired,
            backupFlowState: .pairingCompleted,
            desktopName: "Studio Mac",
            sessionID: payload.sessionID,
            transport: .lan,
            message: "Pairing succeeded for \(payload.sessionID)."
        )
    }
}

private struct StoppedPairingService: PairingService {
    func startPairing(using payload: PairingQRCodePayload) async -> PairingStatus {
        PairingStatus(
            phase: .failed,
            backupFlowState: .pairingStopped,
            desktopName: "Studio Mac",
            sessionID: payload.sessionID,
            transport: nil,
            message: "Desktop canceled this pairing request."
        )
    }
}

private struct StaticQRCodePayloadDecoder: QRCodePayloadDecoding {
    func decode(scannedValue: String) -> Result<PairingQRCodePayload, QRCodePayloadDecoderError> {
        .success(.demo)
    }
}

private struct FailingQRCodePayloadDecoder: QRCodePayloadDecoding {
    let error: QRCodePayloadDecoderError

    func decode(scannedValue: String) -> Result<PairingQRCodePayload, QRCodePayloadDecoderError> {
        .failure(error)
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

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        .skipped
    }
}

private actor RecordingTelemetryClient: TelemetryClient {
    private var records: [RecordedTelemetry] = []

    func record(event: MobileTelemetryEvent, attributes: MobileTelemetryAttributes) async {
        records.append(
            RecordedTelemetry(
                event: event,
                attributes: attributes
            )
        )
    }

    func latestRecord(for event: MobileTelemetryEvent) -> RecordedTelemetry? {
        records.last(where: { $0.event == event })
    }
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

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        .skipped
    }
}

private actor CleanupTrackingTransferService: TransferService {
    private let completedSnapshot: TransferSnapshot
    private var cleanupCalls = 0

    init(completedSnapshot: TransferSnapshot) {
        self.completedSnapshot = completedSnapshot
    }

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        progress(completedSnapshot)
        return completedSnapshot
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
        completedSnapshot
    }

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        cleanupCalls += 1
        return .removed(completedSnapshot.transferredCount)
    }

    func cleanupCallCount() -> Int {
        cleanupCalls
    }
}

private actor StopTrackingTransferService: TransferService {
    private var stopCalls = 0

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        progress(.demo)
        return .demo
    }

    func stopTransfer(current: TransferSnapshot) async -> InterruptionReason {
        stopCalls += 1
        return .stoppedByUser
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

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        .skipped
    }

    func stopCallCount() -> Int {
        stopCalls
    }
}

private actor ForegroundRecoveryTrackingTransferService: TransferService {
    private var foregroundRecoveryCalls = 0

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

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        .skipped
    }

    func handleAppDidBecomeActive() async {
        foregroundRecoveryCalls += 1
    }

    func foregroundRecoveryCallCount() -> Int {
        foregroundRecoveryCalls
    }
}

private actor DelayedTransferService: TransferService {
    private let inFlightSnapshot: TransferSnapshot
    private let finalSnapshot: TransferSnapshot
    private let transferDurationNanoseconds: UInt64
    private var stopCalls = 0
    private var snapshot: TransferSnapshot?

    init(
        inFlightSnapshot: TransferSnapshot,
        finalSnapshot: TransferSnapshot,
        transferDurationNanoseconds: UInt64
    ) {
        self.inFlightSnapshot = inFlightSnapshot
        self.finalSnapshot = finalSnapshot
        self.transferDurationNanoseconds = transferDurationNanoseconds
    }

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        snapshot = inFlightSnapshot
        progress(inFlightSnapshot)
        try? await Task.sleep(nanoseconds: transferDurationNanoseconds)
        snapshot = finalSnapshot
        return finalSnapshot
    }

    func stopTransfer(current: TransferSnapshot) async -> InterruptionReason {
        _ = current
        stopCalls += 1
        return .stoppedByUser
    }

    func resumeTransfer(from snapshot: TransferSnapshot, progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        self.snapshot = snapshot
        progress(snapshot)
        return snapshot
    }

    func completeTransfer(current: TransferSnapshot) async -> TransferSnapshot {
        current
    }

    func progressSnapshot() async -> TransferSnapshot? {
        snapshot
    }

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        .skipped
    }

    func stopCallCount() -> Int {
        stopCalls
    }
}

private actor SlowAppStateStore: AppStateStore {
    private let snapshot: LaunchSnapshot
    private let saveDelay: Duration

    init(snapshot: LaunchSnapshot = .firstLaunch, saveDelay: Duration) {
        self.snapshot = snapshot
        self.saveDelay = saveDelay
    }

    func loadLaunchSnapshot() async -> LaunchSnapshot {
        snapshot
    }

    func saveLaunchSnapshot(_ snapshot: LaunchSnapshot) async {
        try? await Task.sleep(for: saveDelay)
    }
}

private actor SlowTelemetryClient: TelemetryClient {
    private let recordDelay: Duration

    init(recordDelay: Duration) {
        self.recordDelay = recordDelay
    }

    func record(event: MobileTelemetryEvent, attributes: MobileTelemetryAttributes) async {
        _ = attributes
        try? await Task.sleep(for: recordDelay)
    }
}

private struct RecordedTelemetry: Equatable {
    let event: MobileTelemetryEvent
    let attributes: MobileTelemetryAttributes
}
