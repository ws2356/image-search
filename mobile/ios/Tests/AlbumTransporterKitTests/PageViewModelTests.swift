import XCTest
@testable import AlbumTransporterKit

@MainActor
final class PageViewModelTests: XCTestCase {
    func test_home_page_view_model_maps_summary_and_actions() async {
        let model = StubPageModel()
        let viewModel = HomePageViewModel(model: model)

        XCTAssertEqual(viewModel.summary, model.homeSummary)

        await viewModel.handlePrimaryAction()
        await viewModel.openScanFlow()

        XCTAssertEqual(model.handleHomePrimaryActionCallCount, 1)
        XCTAssertEqual(model.openScanFlowCallCount, 1)
    }

    func test_pairing_page_view_model_maps_status_binding_and_actions() async {
        let model = StubPageModel()
        let viewModel = PairingPageViewModel(model: model)

        XCTAssertEqual(viewModel.status, model.pairingStatus)
        XCTAssertEqual(viewModel.scannedQRCodeBinding.wrappedValue, "")

        viewModel.scannedQRCodeBinding.wrappedValue = "qr-value"
        XCTAssertEqual(model.scannedQRCodeValue, "qr-value")

        await viewModel.beginPairing()
        await viewModel.scanAgain()
        await viewModel.goBack()

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
        await viewModel.startBackup()
        await viewModel.goBack()

        XCTAssertEqual(model.setRemoveAfterBackupEnabledCallCount, 1)
        XCTAssertTrue(model.removeAfterBackupEnabled)
        XCTAssertEqual(model.startBackupCallCount, 1)
        XCTAssertEqual(model.returnHomeCallCount, 1)
    }

    func test_transfer_page_view_model_maps_snapshot_and_stop_action() {
        let model = StubPageModel()
        let viewModel = TransferPageViewModel(model: model)

        XCTAssertEqual(viewModel.snapshot, model.transferSnapshot)

        viewModel.requestStopTransfer()
        XCTAssertEqual(model.requestStopTransferCallCount, 1)
    }

    func test_completion_page_view_model_maps_summary_and_return_action() async {
        let model = StubPageModel()
        let viewModel = CompletionPageViewModel(model: model)

        XCTAssertEqual(viewModel.summary, model.completionSummary)

        await viewModel.returnHome()
        XCTAssertEqual(model.returnHomeCallCount, 1)
    }
}

@MainActor
private final class StubPageModel: AppPageModeling {
    var homeSummary = HomeSummary.firstLaunch
    var pairingStatus = PairingStatus.idle
    var permissionSummary = PermissionSummary.demo
    var removeAfterBackupEnabled = false
    var transferSnapshot = TransferSnapshot.demo
    var completionSummary = CompletionSummary.demo
    var scannedQRCodeValue = ""

    var handleHomePrimaryActionCallCount = 0
    var openScanFlowCallCount = 0
    var beginPairingCallCount = 0
    var returnHomeCallCount = 0
    var startBackupCallCount = 0
    var setRemoveAfterBackupEnabledCallCount = 0
    var requestStopTransferCallCount = 0

    func handleHomePrimaryAction() async {
        handleHomePrimaryActionCallCount += 1
    }

    func openScanFlow() async {
        openScanFlowCallCount += 1
    }

    func beginPairing() async {
        beginPairingCallCount += 1
    }

    func returnHome() async {
        returnHomeCallCount += 1
    }

    func startBackup() async {
        startBackupCallCount += 1
    }

    func setRemoveAfterBackupEnabled(_ isEnabled: Bool) {
        removeAfterBackupEnabled = isEnabled
        setRemoveAfterBackupEnabledCallCount += 1
    }

    func requestStopTransfer() {
        requestStopTransferCallCount += 1
    }
}
