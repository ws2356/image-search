import XCTest
@testable import AlbumTransporterKit

@MainActor
final class PageViewModelTests: XCTestCase {
    func test_home_page_view_model_maps_summary_and_actions() async {
        let model = StubPageModel()
        let viewModel = HomePageViewModel(model: model)

        await viewModel.refreshSummary()
        XCTAssertEqual(viewModel.summary, model.homeSummary)

        await viewModel.handlePrimaryActionTapped()

        XCTAssertEqual(model.homeScanActionCallCount, 1)
    }

    func test_home_page_view_model_renders_stopped_transfer_summary_on_refresh() async {
        let model = StubPageModel()
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
                etaDescription: nil,
                statusMessage: "Stopped.",
                guidanceMessage: "",
                isIncompleteLibrary: false
            )
        )
        let viewModel = HomePageViewModel(model: model)

        await viewModel.refreshSummary()

        XCTAssertEqual(viewModel.summary.lastBackupDescription, "Stopped after 3 of 10 items.")
        XCTAssertEqual(
            viewModel.summary.previouslyTransferredDescription,
            "3 items sent in the most recent session."
        )
        XCTAssertEqual(viewModel.summary.desktopName, "Desk Mac")
    }

    func test_scanning_page_view_model_maps_status_binding_and_actions() async {
        let model = StubPageModel()
        let viewModel = ScanningPageViewModel(model: model)

        XCTAssertEqual(viewModel.status, model.pairingStatus)
        XCTAssertEqual(model.scannedQRCodeValue, "")

        await viewModel.onQRScanned(scannedValue: "qr-value")
        await viewModel.backTapped()
        viewModel.scannerFailed()
        await Task.yield()

        XCTAssertEqual(model.scannedQRCodeValue, "qr-value")
        XCTAssertEqual(model.beginPairingCallCount, 1)
        XCTAssertEqual(model.returnHomeCallCount, 1)
        XCTAssertEqual(model.scanFailureCallCount, 1)
    }

    func test_pairing_page_view_model_maps_status_binding_and_actions() async {
        let model = StubPageModel()
        let viewModel = PairingPageViewModel(model: model)

        XCTAssertEqual(viewModel.status, model.pairingStatus)

        await viewModel.scanAgainTapped()
        await viewModel.backTapped()

        XCTAssertEqual(model.openScanRouteCallCount, 1)
        XCTAssertEqual(model.returnHomeCallCount, 1)
    }

    func test_permissions_page_view_model_maps_summary_and_actions() async {
        let model = StubPageModel()
        let viewModel = PermissionsPageViewModel(model: model)

        XCTAssertEqual(viewModel.summary, model.permissionSummary)
        XCTAssertEqual(viewModel.removeAfterBackupEnabled, model.removeAfterBackupEnabled)

        viewModel.setRemoveAfterBackupEnabled(true)
        await viewModel.startPreflight()
        XCTAssertTrue(viewModel.isShowingMediaAccessAlert)
        await viewModel.goBack()

        XCTAssertEqual(model.setRemoveAfterBackupEnabledCallCount, 1)
        XCTAssertTrue(model.removeAfterBackupEnabled)
        let loadCallCount = await model.permissionServiceLoadCallCount()
        XCTAssertEqual(loadCallCount, 1)
        XCTAssertEqual(model.beginTelemetrySpanCallCount, 1)
        XCTAssertEqual(model.recordedTelemetryEvents.first, .backupPreflightStarted)
        XCTAssertFalse(viewModel.isShowingMediaAccessAlert)
        XCTAssertEqual(model.returnHomeCallCount, 1)
    }

    func test_transfer_page_view_model_maps_snapshot_and_stop_action() {
        let model = StubPageModel()
        let viewModel = TransferPageViewModel(model: model)

        XCTAssertEqual(viewModel.snapshot, .demo)

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
        let model = StubPageModel()
        await model.transferServiceActor.configureProgressSequence(
            initialSnapshot: TransferSnapshot(
                transferredCount: 1,
                totalCount: 5,
                failedCount: 0,
                transport: .lan,
                etaDescription: "4 min remaining",
                statusMessage: "Starting transfer.",
                guidanceMessage: "Keep the app in the foreground.",
                isIncompleteLibrary: false
            ),
            finalSnapshot: TransferSnapshot(
                transferredCount: 5,
                totalCount: 5,
                failedCount: 0,
                transport: .lan,
                etaDescription: nil,
                statusMessage: "Transfer finished.",
                guidanceMessage: "Waiting for desktop confirmation.",
                isIncompleteLibrary: false
            ),
            callbackDelayNanoseconds: 200_000_000
        )
        let viewModel = TransferPageViewModel(model: model)

        let transferTask = Task { @MainActor in
            await viewModel.orchestrateTransfer()
        }

        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(viewModel.snapshot.transferredCount, 1)
        XCTAssertEqual(viewModel.snapshot.totalCount, 5)

        await transferTask.value
    }

}

@MainActor
private final class StubPageModel: PermissionsPageModeling, TransferPageModeling {
    var homeSummary = HomeSummary.firstLaunch
    var backupFlowState: MobileBackupFlowState = .pendingPairing
    var pairingStatus = PairingStatus.idle
    var permissionSummary = PermissionSummary.demo
    var removeAfterBackupEnabled = false
    var errorSummary = ErrorSummary.generic
    var scannedQRCodeValue = ""
    var route = AppRoute.home
    var isShowingLowBatteryWarning = false
    var isShowingMediaAccessAlert = false
    var isShowingRemoveAfterBackupPrompt = false
    var mediaAccessAlertMessage = "Media access recommended."
    let permissionServiceActor = StubPermissionService(summary: .demo)
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
    var setRemoveAfterBackupEnabledCallCount = 0
    var requestStopTransferCallCount = 0
    var beginTelemetrySpanCallCount = 0
    var recordedTelemetryEvents: [MobileTelemetryEvent] = []

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
                if target == .removeTransferredMedia {
                    setRemoveAfterBackupEnabled(true)
                } else if target == .keepOriginals {
                    setRemoveAfterBackupEnabled(false)
                }
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

    func setRemoveAfterBackupEnabled(_ isEnabled: Bool) {
        removeAfterBackupEnabled = isEnabled
        setRemoveAfterBackupEnabledCallCount += 1
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

    func beginTelemetrySpan(_ span: MobileTelemetrySpan, attributes: MobileTelemetryAttributes) {
        _ = span
        _ = attributes
        beginTelemetrySpanCallCount += 1
    }

    func recordTelemetry(_ event: MobileTelemetryEvent, attributes: MobileTelemetryAttributes) {
        _ = attributes
        recordedTelemetryEvents.append(event)
    }

    func persistSnapshot() {}

    func abortPreflightAndReturnHome(reason: String) async {
        _ = reason
    }

    func recordDialogView(name: String) {}

    func recordInteraction(name: String, location: String) {}
}

private actor StubPermissionService: PermissionService {
    private var summary: PermissionSummary
    private var loadPermissionSummaryCallCount = 0

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
}

private actor StubTransferService: TransferService {
    private var snapshot: TransferSnapshot = .demo
    private var completionState: TransferCompletionState?
    private var progressSequence: (initial: TransferSnapshot, final: TransferSnapshot, delayNanoseconds: UInt64)?

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
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
}
