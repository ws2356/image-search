import XCTest
@testable import AlbumTransporterKit

@MainActor
final class PageViewModelTests: XCTestCase {
    func test_home_page_view_model_maps_summary_and_actions() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        let viewModel = HomePageViewModel(model: model, telemetryService: telemetryService)

        await viewModel.refreshSummary()
        XCTAssertEqual(viewModel.summary, model.homeSummary)

        await viewModel.handlePrimaryActionTapped()

        XCTAssertEqual(model.homeScanActionCallCount, 1)
    }

    func test_home_page_view_model_renders_stopped_transfer_summary_on_refresh() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        model.backupFlowState = .transferStopped
        model.pairingStatus = PairingStatus(
            phase: .paired,
            backupFlowState: .transferStopped,
            desktopName: "Desk Mac",
            sessionID: "session-1",
            transport: .lan,
            message: "Connected."
        )
        await model.transferServiceActor.stageTransferSnapshot(
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
        let viewModel = HomePageViewModel(model: model, telemetryService: telemetryService)

        await viewModel.refreshSummary()

        XCTAssertEqual(viewModel.summary.lastBackupDescription, "Stopped after 3 of 10 items.")
        XCTAssertEqual(
            viewModel.summary.previouslyTransferredDescription,
            "3 items sent in the most recent session."
        )
        XCTAssertEqual(viewModel.summary.desktopName, "Desk Mac")
    }

    func test_scanning_page_view_model_maps_status_binding_and_actions() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        let viewModel = ScanningPageViewModel(model: model, telemetryService: telemetryService)

        XCTAssertEqual(viewModel.status, model.pairingStatus)
        XCTAssertEqual(model.scannedQRCodeValue, "")

        await viewModel.onQRScanned(scannedValue: "qr-value")
        await viewModel.backTapped()
        await viewModel.openSettingsTapped()
        await viewModel.scannerFailed()

        XCTAssertEqual(model.scannedQRCodeValue, "qr-value")
        XCTAssertEqual(model.beginPairingCallCount, 1)
        XCTAssertEqual(model.returnHomeCallCount, 2)
        XCTAssertEqual(model.scanFailureCallCount, 1)
    }

    func test_error_page_view_model_maps_summary_and_actions() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        let viewModel = ErrorPageViewModel(model: model, telemetryService: telemetryService)

        XCTAssertEqual(viewModel.summary, model.errorSummary)

        await viewModel.retryTapped()
        await viewModel.cancelTapped()

        XCTAssertEqual(model.openScanRouteCallCount, 1)
        XCTAssertEqual(model.returnHomeCallCount, 1)
    }

    func test_pairing_page_view_model_maps_status_binding_and_actions() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        let viewModel = PairingPageViewModel(model: model, telemetryService: telemetryService)

        XCTAssertEqual(viewModel.status, model.pairingStatus)

        await viewModel.scanAgainTapped()
        await viewModel.backTapped()

        XCTAssertEqual(model.openScanRouteCallCount, 1)
        XCTAssertEqual(model.returnHomeCallCount, 1)
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

    func test_transfer_page_view_model_maps_snapshot_and_stop_action() {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        let viewModel = TransferPageViewModel(
            model: model,
            telemetryService: telemetryService,
            pollingIntervalNanoseconds: 10_000_000
        )

        XCTAssertEqual(viewModel.snapshot.transferredCount, 0)
        XCTAssertEqual(viewModel.snapshot.totalCount, 0)
        XCTAssertEqual(viewModel.snapshot.transport, .lan)

        viewModel.requestStopTransfer()
        let expectation = expectation(description: "stop transfer routed via page result")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertEqual(model.requestStopTransferCallCount, 1)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
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
        let viewModel = TransferPageViewModel(model: model, telemetryService: telemetryService)

        let transferTask = Task { @MainActor in
            await viewModel.orchestrateTransfer()
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.snapshot.transferredCount, 1)
        XCTAssertEqual(viewModel.snapshot.totalCount, 5)

        await transferTask.value
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
        let viewModel = TransferPageViewModel(model: model, telemetryService: telemetryService)

        await viewModel.orchestrateTransfer()

        let completionState = await model.transferServiceActor.transferCompletionState()
        XCTAssertNotNil(completionState?.sessionDuration)
        XCTAssertGreaterThan(completionState?.sessionDuration ?? 0, 0)
    }

    func test_transfer_page_view_model_allows_second_backup_session() async {
        let telemetryService = StubTelemetryService()
        let model = StubPageModel(telemetryServiceActor: telemetryService)
        model.route = .transfer
        let viewModel = TransferPageViewModel(model: model, telemetryService: telemetryService)

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

}

@MainActor
private final class StubPageModel: PermissionsPageModeling, TransferPageModeling {
    var homeSummary = HomeSummary.firstLaunch
    var backupFlowState: MobileBackupFlowState = .pendingPairing
    var pairingStatus = PairingStatus.idle
    var permissionSummary = PermissionSummary.demo
    var errorSummary = ErrorSummary.generic
    var scannedQRCodeValue = ""
    var route = AppRoute.home
    var isShowingLowBatteryWarning = false
    var isShowingMediaAccessAlert = false
    var isShowingRemoveAfterBackupPrompt = false
    var mediaAccessAlertMessage = "Media access recommended."
    let permissionServiceActor = StubPermissionService(summary: .demo)
    let telemetryServiceActor: StubTelemetryService
    let transferServiceActor = StubTransferService()
    var permissionService: PermissionService { permissionServiceActor }
    var transferServiceForPageModels: TransferService { transferServiceActor }
    var transferServiceForTransferView: TransferService { transferServiceActor }

    var homeScanActionCallCount = 0
    var openScanRouteCallCount = 0
    var beginPairingCallCount = 0
    var returnHomeCallCount = 0
    var scanFailureCallCount = 0
    var pairingFailureCallCount = 0
    var requestStopTransferCallCount = 0

    init(telemetryServiceActor: StubTelemetryService = StubTelemetryService()) {
        self.telemetryServiceActor = telemetryServiceActor
    }

    func handleResultForPage(_ page: AppRoute, result: PageResult, target: PageTarget?) async {
        switch page {
        case .home:
            if result == .success {
                homeScanActionCallCount += 1
            } else if result == .cancel {
                returnHomeCallCount += 1
            }
        case .pair:
            if result == .success {
                openScanRouteCallCount += 1
            } else if result == .cancel {
                returnHomeCallCount += 1
            } else if result == .failure {
                pairingFailureCallCount += 1
            }
        case .permissions:
            if result == .success {
            } else if result == .cancel {
                returnHomeCallCount += 1
            }
        case .transfer:
            if result == .success, target == .primary {
                requestStopTransfer()
            } else if result == .cancel, target == .stopTransferConfirmed {
                if let snapshot = await transferServiceActor.progressSnapshot() {
                    await confirmStopTransfer(currentSnapshot: snapshot)
                }
            }
        case .completed:
            if result == .success || result == .cancel {
                returnHomeCallCount += 1
            }
        case .error:
            if result == .success {
                openScanRouteCallCount += 1
            } else {
                returnHomeCallCount += 1
            }
        case .scan:
            if result == .success {
                beginPairingCallCount += 1
            } else if result == .cancel {
                returnHomeCallCount += 1
            } else if result == .failure {
                scanFailureCallCount += 1
            }
        }
    }

    func requestStopTransfer() {
        requestStopTransferCallCount += 1
    }

    func confirmStopTransfer(currentSnapshot: TransferSnapshot) async {
        await transferServiceActor.stageTransferSnapshot(currentSnapshot)
    }

    func completeTransfer(with snapshot: TransferSnapshot) async {
        await transferServiceActor.stageTransferSnapshot(snapshot)
    }

    func permissionServiceLoadCallCount() async -> Int {
        await permissionServiceActor.loadCallCount()
    }

    func persistSnapshot() {}

    func abortPreflightAndReturnHome(reason: String) async {
        _ = reason
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

    func recordTelemetry(_ event: MobileTelemetryEvent, attributes: MobileTelemetryAttributes) {
        _ = attributes
        recordedEvents.append(event)
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
}

private actor StubTransferService: TransferService {
    private var snapshot: TransferSnapshot = .demo
    private var completionState: TransferCompletionState?
    private var progressSequence: (initial: TransferSnapshot, final: TransferSnapshot, delayNanoseconds: UInt64)?
    private var startTransferInvocations = 0

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        startTransferInvocations += 1
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

    func stopTransfer(current: TransferSnapshot) async -> InterruptionReason {
        .stoppedByUser
    }

    func resumeTransfer(
        from snapshot: TransferSnapshot,
        progress: @escaping @Sendable (TransferSnapshot) -> Void
    ) async -> TransferSnapshot {
        snapshot
    }

    func completeTransfer(current: TransferSnapshot) async -> TransferSnapshot {
        snapshot = current
        return current
    }

    func progressSnapshot() async -> TransferSnapshot? {
        snapshot
    }

    func stageTransferSnapshot(_ snapshot: TransferSnapshot) async {
        self.snapshot = snapshot
    }

    func transferCompletionState() async -> TransferCompletionState? {
        completionState
    }

    func stageTransferCompletionState(_ completionState: TransferCompletionState?) async {
        self.completionState = completionState
        if let snapshot = completionState?.snapshot {
            self.snapshot = snapshot
        }
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
