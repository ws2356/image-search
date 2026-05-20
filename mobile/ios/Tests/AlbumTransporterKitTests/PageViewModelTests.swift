import XCTest
@testable import AlbumTransporterKit

@MainActor
final class PageViewModelTests: XCTestCase {
    func test_home_page_view_model_maps_summary_and_actions() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        let viewModel = HomePageViewModel(
            model: model,
            telemetryService: telemetryService,
            transportResolver: model.transferService
        )

        await viewModel.refreshSummary()
        XCTAssertEqual(viewModel.summary, model.homeSummary)

        await viewModel.handlePrimaryActionTapped()

        XCTAssertEqual(model.homeScanActionCallCount, 1)
    }

    func test_home_page_view_model_renders_stopped_transfer_summary_on_refresh() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        model.backupFlowState = .transferStopped
        await model.backupSessionProvider.saveBackupSession(
            BackupSession(
                sessionID: "session-1",
                desktopName: "Desk Mac",
                status: .transferStopped,
                updatedAt: Date()
            )
        )
        await model.transferServiceActor.setSnapshot(
            TransferSnapshot(
                transferredCount: 3,
                totalCount: 10,
                failedCount: 1,
                transport: .lan,
                etaMinutes: nil,
                statusMessage: "Stopped.",
                guidanceMessage: "",
                isIncompleteLibrary: false
            )
        )
        let viewModel = HomePageViewModel(
            model: model,
            telemetryService: telemetryService,
            transportResolver: model.transferService
        )

        await viewModel.refreshSummary()

        XCTAssertEqual(viewModel.summary.lastBackupDescription, "Stopped after 3 of 10 items.")
        XCTAssertEqual(
            viewModel.summary.previousTransferDescription,
            "3 items sent in the most recent session."
        )
        XCTAssertEqual(viewModel.summary.desktopName, "Desk Mac")
    }

    func test_home_page_view_model_records_diagnostic_checkpoint_on_refresh() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        let viewModel = HomePageViewModel(
            model: model,
            telemetryService: telemetryService,
            transportResolver: model.transferService
        )

        await viewModel.refreshSummary()

        let diagnosticRecord = telemetryService.latestRecord(for: .diagnosticCheckpoint)
        XCTAssertEqual(diagnosticRecord?.attributes["diagnostic.area"], .string("home_summary_refreshed"))
        XCTAssertEqual(diagnosticRecord?.attributes["backup.session_present"], .bool(false))
        XCTAssertEqual(diagnosticRecord?.attributes["transfer.snapshot_present"], .bool(true))
        XCTAssertEqual(diagnosticRecord?.attributes["transfer.transport"], .string("lan"))
    }

    func test_home_page_view_model_refreshes_summary_on_backup_session_publisher_change() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        let viewModel = HomePageViewModel(
            model: model,
            telemetryService: telemetryService,
            transportResolver: model.transferService
        )

        // Allow initial subscription emission to be processed.
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(viewModel.summary.lastBackupDescription, "No session history expected before load")

        // Simulate backupSessionProvider.load() completing with a persisted session.
        await model.backupSessionProvider.saveBackupSession(
            BackupSession(
                sessionID: "session-1",
                desktopName: "My PC",
                status: .transferCompleted,
                updatedAt: Date()
            )
        )

        // Allow the subscription-triggered refreshSummary Task to complete.
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.summary.lastBackupDescription, "Last backup completed just now.")
        XCTAssertEqual(viewModel.summary.desktopName, "My PC")
    }

    func test_scanning_page_view_model_maps_actions() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        let viewModel = ScanningPageViewModel(model: model, telemetryService: telemetryService)

        await viewModel.onQRScanned(scannedValue: "qr-value")
        await viewModel.backTapped()
        await viewModel.openSettingsTapped()
        await viewModel.scannerFailed()

        XCTAssertEqual(model.route, .pair(qrString: "qr-value"))
        XCTAssertEqual(model.beginPairingCallCount, 1)
        XCTAssertEqual(model.returnHomeCallCount, 2)
        XCTAssertEqual(model.scanFailureCallCount, 1)
    }

    func test_error_page_view_model_maps_summary_and_actions() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        let expectedSummary = ErrorSummary(title: "Preview Error", message: "Preview error message.")
        model.route = .error(expectedSummary)
        let viewModel = ErrorPageViewModel(model: model, telemetryService: telemetryService)

        XCTAssertEqual(viewModel.summary, expectedSummary)

        await viewModel.retryTapped()
        await viewModel.cancelTapped()

        XCTAssertEqual(model.openScanRouteCallCount, 1)
        XCTAssertEqual(model.returnHomeCallCount, 1)
    }

    func test_pairing_page_view_model_maps_actions() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        let viewModel = PairingPageViewModel(
            model: model,
            telemetryService: telemetryService,
            qrCodePayloadDecoder: URLQueryQRCodePayloadDecoder()
        )

        await viewModel.backTapped()

        XCTAssertEqual(model.returnHomeCallCount, 1)
    }

    func test_pairing_page_view_model_orchestrates_pairing_result() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        model.route = .pair(qrString: PairingQRCodePayload.demoScanValue)
        let viewModel = PairingPageViewModel(
            model: model,
            telemetryService: telemetryService,
            qrCodePayloadDecoder: URLQueryQRCodePayloadDecoder()
        )

        await viewModel.orchestratePairing()

        let startPairingCallCount = await model.pairingServiceActor.startPairingCallCount()
        XCTAssertEqual(startPairingCallCount, 1)
        XCTAssertEqual(model.backupSessionProvider.backupSession?.sessionID, PairingQRCodePayload.demo.sessionID)
        XCTAssertEqual(model.backupSessionProvider.backupSession?.status, .pairingCompleted)
        let diagnosticRecord = telemetryService.latestRecord(for: .diagnosticCheckpoint)
        XCTAssertEqual(diagnosticRecord?.attributes["diagnostic.area"], .string("pairing_service_result"))
        XCTAssertEqual(diagnosticRecord?.attributes["pairing.result"], .string("success"))
    }

    func test_pairing_page_view_model_ignores_reentry_after_pairing_leaves_loading_state() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        model.route = .pair(qrString: PairingQRCodePayload.demoScanValue)
        model.backupFlowState = .pairingStopped
        let viewModel = PairingPageViewModel(
            model: model,
            telemetryService: telemetryService,
            qrCodePayloadDecoder: URLQueryQRCodePayloadDecoder()
        )

        await viewModel.orchestratePairing()

        let startPairingCallCount = await model.pairingServiceActor.startPairingCallCount()
        XCTAssertEqual(startPairingCallCount, 0)
    }

    func test_permissions_page_view_model_maps_summary_and_actions() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        let viewModel = PermissionsPageViewModel(model: model, telemetryService: telemetryService)

        XCTAssertEqual(viewModel.summary, model.permissionSummary)

        await viewModel.startPreflight()
        XCTAssertTrue(viewModel.isShowingMediaAccessAlert)
        await viewModel.goBack()

        let loadCallCount = await model.permissionServiceLoadCallCount()
        XCTAssertEqual(loadCallCount, 1)
        XCTAssertEqual(telemetryService.beginSpanCallCount, 1)
        XCTAssertEqual(telemetryService.recordedEvents.first, .backupPreflightStarted)
        XCTAssertFalse(viewModel.isShowingMediaAccessAlert)
        XCTAssertEqual(model.returnHomeCallCount, 1)
    }

    func test_permissions_page_view_model_advances_prompts_in_order() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        let viewModel = PermissionsPageViewModel(model: model, telemetryService: telemetryService)

        await viewModel.startPreflight()
        XCTAssertTrue(viewModel.isShowingMediaAccessAlert)
        XCTAssertFalse(viewModel.isShowingLowBatteryWarning)
        XCTAssertFalse(viewModel.isShowingRemoveAfterBackupPrompt)

        await viewModel.continueAfterMediaAccessUpdate()
        XCTAssertFalse(viewModel.isShowingMediaAccessAlert)
        XCTAssertTrue(viewModel.isShowingLowBatteryWarning)
        XCTAssertFalse(viewModel.isShowingRemoveAfterBackupPrompt)

        await viewModel.continuePastLowBattery()
        XCTAssertFalse(viewModel.isShowingLowBatteryWarning)
        XCTAssertTrue(viewModel.isShowingRemoveAfterBackupPrompt)
    }

    func test_permissions_page_view_model_ignores_repeated_preflight_start_while_prompt_active() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        let viewModel = PermissionsPageViewModel(model: model, telemetryService: telemetryService)

        await viewModel.startPreflight()
        await viewModel.startPreflight()

        let loadCallCount = await model.permissionServiceLoadCallCount()
        XCTAssertEqual(loadCallCount, 1)
        XCTAssertEqual(telemetryService.beginSpanCallCount, 1)
        XCTAssertTrue(viewModel.isShowingMediaAccessAlert)
    }

    func test_transfer_page_view_model_maps_snapshot_and_stop_action() {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        let viewModel = TransferPageViewModel(
            model: model,
            telemetryService: telemetryService,
            transportResolver: model.transferService,
            pollingIntervalNanoseconds: 10_000_000
        )

        XCTAssertEqual(viewModel.snapshot.transferredCount, 0)
        XCTAssertEqual(viewModel.snapshot.totalCount, 0)
        XCTAssertEqual(viewModel.snapshot.transport, .lan)

        viewModel.requestStopTransfer()
        XCTAssertTrue(viewModel.isShowingStopConfirmation)
    }

    func test_transfer_page_view_model_disables_idle_timer_when_usb_transport_is_alive() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        let idleTimerController = StubIdleTimerController()
        let batteryLevelProvider = StubBatteryLevelProvider(level: 0.5)
        await model.transferServiceActor.setUSBTransportAlive(true)
        let viewModel = TransferPageViewModel(
            model: model,
            telemetryService: telemetryService,
            transportResolver: model.transferService,
            idleTimerController: idleTimerController,
            batteryLevelProvider: batteryLevelProvider,
            pollingIntervalNanoseconds: 10_000_000
        )

        await viewModel.loadFromViewLifecycle()

        XCTAssertTrue(idleTimerController.isIdleTimerDisabled)
    }

    func test_transfer_page_view_model_resets_idle_timer_when_usb_is_not_alive_and_battery_is_not_above_threshold() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        let idleTimerController = StubIdleTimerController()
        let batteryLevelProvider = StubBatteryLevelProvider(level: 0.95)
        let viewModel = TransferPageViewModel(
            model: model,
            telemetryService: telemetryService,
            transportResolver: model.transferService,
            idleTimerController: idleTimerController,
            batteryLevelProvider: batteryLevelProvider,
            pollingIntervalNanoseconds: 10_000_000
        )

        await viewModel.loadFromViewLifecycle()
        XCTAssertTrue(idleTimerController.isIdleTimerDisabled)

        batteryLevelProvider.level = 0.89
        await model.transferServiceActor.setUSBTransportAlive(false)
        await viewModel.loadFromViewLifecycle()

        XCTAssertFalse(idleTimerController.isIdleTimerDisabled)
    }

    func test_transfer_page_view_model_applies_live_progress_callbacks() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        await model.transferServiceActor.configureProgressSequence(
            initialSnapshot: TransferSnapshot(
                transferredCount: 1,
                totalCount: 5,
                failedCount: 0,
                transport: .lan,
                etaMinutes: 4,
                statusMessage: "Starting transfer.",
                guidanceMessage: "Keep the app in the foreground.",
                isIncompleteLibrary: false
            ),
            finalSnapshot: TransferSnapshot(
                transferredCount: 5,
                totalCount: 5,
                failedCount: 0,
                transport: .lan,
                etaMinutes: nil,
                statusMessage: "Transfer finished.",
                guidanceMessage: "Waiting for desktop confirmation.",
                isIncompleteLibrary: false
            ),
            callbackDelayNanoseconds: 200_000_000
        )
        let viewModel = TransferPageViewModel(
            model: model,
            telemetryService: telemetryService,
            transportResolver: model.transferService
        )

        let transferTask = Task { @MainActor in
            await viewModel.orchestrateTransfer()
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.snapshot.transferredCount, 1)
        XCTAssertEqual(viewModel.snapshot.totalCount, 5)

        await transferTask.value
        XCTAssertTrue(
            telemetryService.records.contains(where: { record in
                record.event == .diagnosticCheckpoint
                    && record.attributes["diagnostic.area"] == .string("transfer_snapshot_applied")
            })
        )
    }

    func test_transfer_page_view_model_stages_completion_duration() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        await model.transferServiceActor.configureProgressSequence(
            initialSnapshot: TransferSnapshot(
                transferredCount: 1,
                totalCount: 3,
                failedCount: 0,
                transport: .lan,
                etaMinutes: 1,
                statusMessage: "Starting transfer.",
                guidanceMessage: "Keep the app in the foreground.",
                isIncompleteLibrary: false
            ),
            finalSnapshot: TransferSnapshot(
                transferredCount: 3,
                totalCount: 3,
                failedCount: 0,
                transport: .lan,
                etaMinutes: nil,
                statusMessage: "Transfer finished.",
                guidanceMessage: "Waiting for desktop confirmation.",
                isIncompleteLibrary: false
            ),
            callbackDelayNanoseconds: 200_000_000
        )
        model.route = .transfer
        let viewModel = TransferPageViewModel(
            model: model,
            telemetryService: telemetryService,
            transportResolver: model.transferService
        )

        await viewModel.orchestrateTransfer()

        let completionState = await model.transferServiceActor.transferCompletionState()
        XCTAssertNotNil(completionState?.sessionDuration)
        XCTAssertGreaterThan(completionState?.sessionDuration ?? 0, 0)
    }

    func test_transfer_page_view_model_allows_second_backup_session() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        model.route = .transfer
        let viewModel = TransferPageViewModel(
            model: model,
            telemetryService: telemetryService,
            transportResolver: model.transferService
        )

        await model.transferServiceActor.configureProgressSequence(
            initialSnapshot: TransferSnapshot(
                transferredCount: 1,
                totalCount: 2,
                failedCount: 0,
                transport: .lan,
                etaMinutes: 1,
                statusMessage: "Starting transfer.",
                guidanceMessage: "Keep the app in the foreground.",
                isIncompleteLibrary: false
            ),
            finalSnapshot: TransferSnapshot(
                transferredCount: 2,
                totalCount: 2,
                failedCount: 0,
                transport: .lan,
                etaMinutes: nil,
                statusMessage: "Transfer finished.",
                guidanceMessage: "Waiting for desktop confirmation.",
                isIncompleteLibrary: false
            ),
            callbackDelayNanoseconds: 50_000_000
        )
        await viewModel.orchestrateTransfer()

        await model.transferServiceActor.configureProgressSequence(
            initialSnapshot: TransferSnapshot(
                transferredCount: 1,
                totalCount: 3,
                failedCount: 0,
                transport: .lan,
                etaMinutes: 2,
                statusMessage: "Starting transfer.",
                guidanceMessage: "Keep the app in the foreground.",
                isIncompleteLibrary: false
            ),
            finalSnapshot: TransferSnapshot(
                transferredCount: 3,
                totalCount: 3,
                failedCount: 0,
                transport: .lan,
                etaMinutes: nil,
                statusMessage: "Transfer finished.",
                guidanceMessage: "Waiting for desktop confirmation.",
                isIncompleteLibrary: false
            ),
            callbackDelayNanoseconds: 50_000_000
        )
        await viewModel.orchestrateTransfer()

        let startTransferCallCount = await model.transferServiceActor.startTransferCallCount()
        XCTAssertEqual(startTransferCallCount, 2)
    }

    func test_transfer_page_view_model_skips_completion_when_route_changes_mid_transfer() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        model.route = .transfer
        await model.transferServiceActor.configureProgressSequence(
            initialSnapshot: TransferSnapshot(
                transferredCount: 1,
                totalCount: 3,
                failedCount: 0,
                transport: .lan,
                etaMinutes: 1,
                statusMessage: "Starting transfer.",
                guidanceMessage: "Keep the app in the foreground.",
                isIncompleteLibrary: false
            ),
            finalSnapshot: TransferSnapshot(
                transferredCount: 3,
                totalCount: 3,
                failedCount: 0,
                transport: .lan,
                etaMinutes: nil,
                statusMessage: "Transfer finished.",
                guidanceMessage: "Waiting for desktop confirmation.",
                isIncompleteLibrary: false
            ),
            callbackDelayNanoseconds: 200_000_000
        )
        let viewModel = TransferPageViewModel(
            model: model,
            telemetryService: telemetryService,
            transportResolver: model.transferService
        )

        let transferTask = Task { @MainActor in
            await viewModel.orchestrateTransfer()
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        model.route = .home

        await transferTask.value

        let completionState = await model.transferServiceActor.transferCompletionState()
        XCTAssertNil(completionState)
    }

}

@MainActor
private final class StubPageModel: PermissionsPageModeling, TransferPageModeling, PairingPageModeling {
    let backupSessionProvider: BackupSessionProviding = AppStateStoreBackedBackupSessionProvider(
        store: InMemoryAppStateStore()
    )
    var homeSummary = HomeViewState(
        desktopName: nil,
        lastBackupDescription: nil,
        previousTransferDescription: nil,
        permissionScope: .limited,
        interruptionWarning: nil
    )
    var backupFlowState: MobileBackupFlowState = .pendingPairing
    var permissionSummary = PermissionSummary.demo
    var route = AppRoute.home
    var isShowingLowBatteryWarning = false
    var isShowingMediaAccessAlert = false
    var isShowingRemoveAfterBackupPrompt = false
    var mediaAccessAlertMessage = "Media access recommended."
    let permissionServiceActor = StubPermissionService(summary: .demo)
    let telemetryServiceActor: StubTelemetryService
    let transferServiceActor = StubTransferService()
    let pairingServiceActor = StubPairingService()
    var permissionService: PermissionService { permissionServiceActor }
    var transferService: TransferService { transferServiceActor }
    var qrCodePayloadDecoderForPairingPage: QRCodePayloadDecoding { StubQRCodePayloadDecoder() }
    var pairingService: PairingService { pairingServiceActor }

    var homeScanActionCallCount = 0
    var openScanRouteCallCount = 0
    var beginPairingCallCount = 0
    var returnHomeCallCount = 0
    var scanFailureCallCount = 0
    var pairingFailureCallCount = 0

    init(telemetryServiceActor: StubTelemetryService = StubTelemetryService()) {
        self.telemetryServiceActor = telemetryServiceActor
    }

    func confirmStopTransfer(currentSnapshot: TransferSnapshot) async {
        await transferServiceActor.setSnapshot(currentSnapshot)
    }

    func completeTransfer(with snapshot: TransferSnapshot) async {
        await transferServiceActor.setSnapshot(snapshot)
    }

    func permissionServiceLoadCallCount() async -> Int {
        await permissionServiceActor.loadCallCount()
    }

    func persistSnapshot() {}

    func onHomeCompleted(with result: HomePageResult) async {
        switch result.result {
        case .success:
            homeScanActionCallCount += 1
        case .failure:
            returnHomeCallCount += 1
        }
    }

    func onScanningCompleted(with result: ScanningPageResult) async {
        switch result.result {
        case .success(let qrValue):
            route = .pair(qrString: qrValue)
            beginPairingCallCount += 1
        case .failure(let error):
            switch error {
            case .scannerFailed:
                scanFailureCallCount += 1
            case .unknown:
                returnHomeCallCount += 1
            }
        }
    }

    func onPairingCompleted(with result: PairingPageResult) async {
        switch result.result {
        case .success(let response):
            await backupSessionProvider.saveBackupSession(
                status: .pairingCompleted,
                sessionID: response.sessionID,
                desktopName: response.desktopName
            )
            openScanRouteCallCount += 1
        case .failure:
            returnHomeCallCount += 1
        }
    }

    func onPermissionsCompleted(with result: PermissionsPageResult) async {
        switch result.result {
        case .success:
            break
        case .failure:
            returnHomeCallCount += 1
        }
    }

    func onTransferCompleted(with result: TransferPageResult) async {
        switch result.result {
        case .success:
            break
        case .failure:
            returnHomeCallCount += 1
        }
    }

    func onCompletionCompleted(with result: CompletionPageResult) async {
        returnHomeCallCount += 1
    }

    func onErrorCompleted(with result: ErrorPageResult) async {
        switch result.result {
        case .success:
            openScanRouteCallCount += 1
        case .failure:
            returnHomeCallCount += 1
        }
    }

}

private actor StubPermissionService: PermissionService {
    private var summary: PermissionSummary
    private var loadPermissionSummaryCallCount = 0
    private var isRemoveAfterBackupEnabled = false

    init(summary: PermissionSummary) {
        self.summary = summary
    }

    func loadPermissionSummary() async -> PermissionSummary {
        loadPermissionSummaryCallCount += 1
        return summary
    }

    func loadCallCount() -> Int {
        loadPermissionSummaryCallCount
    }

    func removeAfterBackupEnabled() async -> Bool {
        isRemoveAfterBackupEnabled
    }

    func setRemoveAfterBackupEnabled(_ isEnabled: Bool) async {
        isRemoveAfterBackupEnabled = isEnabled
    }
}

@MainActor
private final class StubTelemetryService: TelemetryService {
    var beginSpanCallCount = 0
    var recordedEvents: [MobileTelemetryEvent] = []
    private(set) var records: [RecordedStubTelemetry] = []

    func recordTelemetry(_ event: MobileTelemetryEvent, attributes: MobileTelemetryAttributes) {
        recordedEvents.append(event)
        records.append(RecordedStubTelemetry(event: event, attributes: attributes))
    }

    func beginTelemetrySpan(_ span: MobileTelemetrySpan, attributes: MobileTelemetryAttributes) {
        _ = span
        _ = attributes
        beginSpanCallCount += 1
    }

    func endTelemetrySpan(
        _ span: MobileTelemetrySpan,
        attributes: MobileTelemetryAttributes,
        status: MobileTelemetrySpanStatus?
    ) {}

    func incrementTelemetryMetric(_ metric: MobileTelemetryMetric, by value: Int, attributes: MobileTelemetryAttributes) {}

    func beginBackupSessionTelemetry() {}
    func recordDialogView(name: String) {}
    func recordInteraction(name: String, location: String) {}
    func forceFlush() {}

    func latestRecord(for event: MobileTelemetryEvent) -> RecordedStubTelemetry? {
        records.last(where: { $0.event == event })
    }
}

private struct RecordedStubTelemetry: Equatable {
    let event: MobileTelemetryEvent
    let attributes: MobileTelemetryAttributes
}

private actor StubTransferService: TransferService {
    private var snapshot: TransferSnapshot = .demo
    private var completionState: TransferCompletionState?
    private var progressSequence: (initial: TransferSnapshot, final: TransferSnapshot, delayNanoseconds: UInt64)?
    private var startTransferInvocations = 0
    private var transferStartedAt: Date?
    private var usbTransportAlive = false

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        startTransferInvocations += 1
        transferStartedAt = Date()
        completionState = nil
        if let progressSequence {
            snapshot = progressSequence.initial
            progress(progressSequence.initial)
            try? await Task.sleep(nanoseconds: progressSequence.delayNanoseconds)
            snapshot = progressSequence.final
            return progressSequence.final
        }
        progress(snapshot)
        return snapshot
    }

    func stopTransfer() async -> InterruptionReason {
        .stoppedByUser
    }

    func completeTransfer() async -> TransferSnapshot {
        snapshot.phase = .completed
        completionState = TransferCompletionState(
            snapshot: snapshot,
            cleanupResult: .skipped,
            completedAt: Date(),
            sessionDuration: transferStartedAt.map { max(0, Date().timeIntervalSince($0)) }
        )
        transferStartedAt = nil
        return snapshot
    }

    func progressSnapshot() async -> TransferSnapshot? {
        snapshot
    }

    func isUSBTransportAlive() async -> Bool {
        usbTransportAlive
    }

    func setSnapshot(_ snapshot: TransferSnapshot) async {
        self.snapshot = snapshot
    }

    func setUSBTransportAlive(_ isAlive: Bool) async {
        usbTransportAlive = isAlive
    }

    func transferCompletionState() async -> TransferCompletionState? {
        completionState
    }

    func configureProgressSequence(
        initialSnapshot: TransferSnapshot,
        finalSnapshot: TransferSnapshot,
        callbackDelayNanoseconds: UInt64
    ) {
        progressSequence = (initialSnapshot, finalSnapshot, callbackDelayNanoseconds)
    }

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        .skipped
    }

    func startTransferCallCount() -> Int {
        startTransferInvocations
    }
}

private actor StubPairingService: PairingService {
    private var startPairingInvocations = 0

    func startPairing(using payload: PairingQRCodePayload) async -> Result<PairingResponse, PairingError> {
        startPairingInvocations += 1
        return .success(
            PairingResponse(
                sessionID: payload.sessionID,
                desktopName: "Studio Mac",
                transport: .lan
            )
        )
    }

    func startPairingCallCount() -> Int {
        startPairingInvocations
    }
}

private struct StubQRCodePayloadDecoder: QRCodePayloadDecoding {
    func decode(scannedValue: String) -> Result<PairingQRCodePayload, QRCodePayloadDecoderError> {
        .success(.demo)
    }
}

@MainActor
private final class StubIdleTimerController: IdleTimerControlling {
    var isIdleTimerDisabled = false
}

@MainActor
private final class StubBatteryLevelProvider: BatteryLevelProviding {
    var level: Float?

    init(level: Float?) {
        self.level = level
    }

    func currentBatteryLevel() -> Float? {
        level
    }
}
