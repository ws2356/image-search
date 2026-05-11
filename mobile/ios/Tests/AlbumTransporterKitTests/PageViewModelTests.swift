import XCTest
@testable import AlbumTransporterKit

@MainActor
final class PageViewModelTests: XCTestCase {
    func test_home_page_view_model_maps_summary_and_actions() async {
        let model = StubPageModel()
        let viewModel = HomePageViewModel(model: model)

        XCTAssertEqual(viewModel.summary, model.homeSummary)

        await viewModel.handlePrimaryActionTapped()
        await viewModel.openScanFlowTapped()

        XCTAssertEqual(model.handleHomePrimaryActionCallCount, 1)
        XCTAssertEqual(model.openScanFlowCallCount, 1)
    }

    func test_pairing_page_view_model_maps_status_binding_and_actions() async {
        let model = StubPageModel()
        let viewModel = PairingPageViewModel(model: model)

        XCTAssertEqual(viewModel.status, model.pairingStatus)
        XCTAssertEqual(model.scannedQRCodeValue, "")

        await viewModel.onQRScanned(scannedValue: "qr-value")
        await viewModel.scanAgainTapped()
        await viewModel.backTapped()

        XCTAssertEqual(model.scannedQRCodeValue, "qr-value")
        XCTAssertEqual(model.beginPairingCallCount, 1)
        XCTAssertEqual(model.openScanFlowCallCount, 1)
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

        XCTAssertEqual(viewModel.snapshot, model.transferSnapshot)

        viewModel.requestStopTransfer()
        let expectation = expectation(description: "stop transfer routed via page result")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 20_000_000)
            XCTAssertEqual(model.requestStopTransferCallCount, 1)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

}

@MainActor
private final class StubPageModel: PermissionsPageModeling, TransferPageModeling {
    var homeSummary = HomeSummary.firstLaunch
    var pairingStatus = PairingStatus.idle
    var permissionSummary = PermissionSummary.demo
    var removeAfterBackupEnabled = false
    var transferSnapshot = TransferSnapshot.demo
    var completionSummary = CompletionSummary.demo
    var errorSummary = ErrorSummary.generic
    var scannedQRCodeValue = ""
    var isShowingLowBatteryWarning = false
    var isShowingMediaAccessAlert = false
    var isShowingRemoveAfterBackupPrompt = false
    var isShowingStopConfirmation = false
    var mediaAccessAlertMessage = "Media access recommended."
    let permissionServiceActor = StubPermissionService(summary: .demo)
    var permissionService: PermissionService { permissionServiceActor }

    var handleHomePrimaryActionCallCount = 0
    var openScanFlowCallCount = 0
    var beginPairingCallCount = 0
    var returnHomeCallCount = 0
    var setRemoveAfterBackupEnabledCallCount = 0
    var requestStopTransferCallCount = 0
    var beginTelemetrySpanCallCount = 0
    var recordedTelemetryEvents: [MobileTelemetryEvent] = []

    func handleResultForPage(_ page: AppRoute, result: PageResult, target: PageTarget?) async {
        switch page {
        case .home:
            if result == .success {
                if target == .secondary {
                    openScanFlowCallCount += 1
                } else {
                    handleHomePrimaryActionCallCount += 1
                }
            } else if result == .cancel {
                returnHomeCallCount += 1
            }
        case .pair:
            if result == .success {
                openScanFlowCallCount += 1
            } else if result == .cancel {
                returnHomeCallCount += 1
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
                await confirmStopTransfer()
            }
        case .completed:
            if result == .success || result == .cancel {
                returnHomeCallCount += 1
            }
        case .error:
            if result == .success {
                openScanFlowCallCount += 1
            } else {
                returnHomeCallCount += 1
            }
        case .scan:
            if result == .success {
                beginPairingCallCount += 1
            } else if result == .cancel {
                returnHomeCallCount += 1
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

    func confirmStopTransfer() async {}

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
