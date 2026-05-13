import SwiftUI
import UIKit
import XCTest
@testable import AlbumTransporterKit

@MainActor
final class AlbumTransporterAppSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        UIView.setAnimationsEnabled(false)
    }

    override func tearDown() {
        SnapshotSupport.releaseWindow()
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    func test_launch_splash_screen() throws {
        let viewController = try SnapshotSupport.loadLaunchScreenViewController()
        try SnapshotSupport.assertSnapshot(pageName: "launch-splash", viewController: viewController)
    }

    func test_home_new_user_page() throws {
        let homeModel = SnapshotAppPageModel(
            homeSummary: .firstLaunch,
            completionSummary: .demo
        )
        let viewController = makeHostedPage(title: "AuBackup") {
            HomeView(viewModel: HomePageViewModel(model: homeModel))
        }
        try SnapshotSupport.assertSnapshot(pageName: "home-new-user", viewController: viewController)
    }

    func test_transfer_in_progress_page() throws {
        let transferModel = SnapshotTransferPageModel(snapshot: .snapshotMarketing)
        let viewController = makeHostedPage(title: "Backup in Progress") {
            TransferSessionView(viewModel: TransferPageViewModel(model: transferModel))
        }
        try SnapshotSupport.assertSnapshot(pageName: "transfer-in-progress", viewController: viewController)
    }

    func test_backup_completion_page() throws {
        let completionModel = SnapshotAppPageModel(
            homeSummary: .firstLaunch,
            completionSummary: .snapshotMarketing
        )
        let completionViewModel = CompletionPageViewModel(model: completionModel)
        let loadedExpectation = expectation(description: "completion summary loaded")
        Task { @MainActor in
            await completionViewModel.reloadSummary()
            loadedExpectation.fulfill()
        }
        wait(for: [loadedExpectation], timeout: 1.0)
        let viewController = makeHostedPage(title: "Backup Complete") {
            CompletionStateView(viewModel: completionViewModel)
        }
        try SnapshotSupport.assertSnapshot(pageName: "backup-completion", viewController: viewController)
    }

    private func makeHostedPage<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> UIViewController {
        let controller = UIHostingController(
            rootView: SnapshotPageHost(title: title, content: content)
        )
        controller.view.backgroundColor = .clear
        return controller
    }
}

private extension TransferSnapshot {
    static let snapshotMarketing = TransferSnapshot(
        transferredCount: 248,
        totalCount: 930,
        failedCount: 0,
        transport: .usb,
        liveTransports: [.usb, .lan],
        transferSpeedText: "42.80 MB/s",
        etaMinutes: 17,
        statusMessage: "Backing up local photos and videos to the paired desktop.",
        guidanceMessage: "USB is active for the fastest backup. Keep your iPhone unlocked and connected until the transfer finishes.",
        isIncompleteLibrary: false
    )
}

private extension CompletionSummary {
    static let snapshotMarketing = CompletionSummary(
        title: "Backup Complete!",
        message: "Desktop confirmed this mobile backup session is complete. Your photos and videos will appear in desktop search as indexing finishes.",
        itemsBackedUp: 930,
        totalTransferredDescription: "24.6 GB",
        durationDescription: "24 min",
        completedAtDescription: "Today at 2:41 PM"
    )
}

@MainActor
private final class SnapshotAppPageModel: AppPageModeling {
    var homeSummary: HomeSummary
    var backupFlowState: MobileBackupFlowState = .pendingPairing
    var pairingStatus = PairingStatus.idle
    var permissionSummary = PermissionSummary.demo
    var permissionService: PermissionService = SnapshotPermissionService()
    var errorSummary = ErrorSummary.generic
    var scannedQRCodeValue = ""
    var transferServiceForPageModels: TransferService { transferService }
    private let transferService: SnapshotTransferService

    init(homeSummary: HomeSummary, completionSummary: CompletionSummary) {
        self.homeSummary = homeSummary
        let snapshot = TransferSnapshot(
            transferredCount: completionSummary.itemsBackedUp ?? 0,
            totalCount: completionSummary.itemsBackedUp ?? 0,
            failedCount: 0,
            transport: .lan,
            etaMinutes: nil,
            statusMessage: "Completed backup snapshot.",
            guidanceMessage: "",
            isIncompleteLibrary: false
        )
        self.transferService = SnapshotTransferService(
            snapshot: snapshot,
            completionState: TransferCompletionState(
                snapshot: snapshot,
                cleanupResult: .skipped,
                completedAt: Date(),
                sessionDuration: nil
            )
        )
    }

    func handleResultForPage(_ page: AppRoute, result: PageResult, target: PageTarget?) async {}
    func requestStopTransfer() {}
    func recordInteraction(name: String, location: String) {}
}

@MainActor
private final class SnapshotTransferPageModel: TransferPageModeling {
    var homeSummary = HomeSummary.firstLaunch
    var backupFlowState: MobileBackupFlowState = .pendingPairing
    var pairingStatus = PairingStatus.idle
    var permissionSummary = PermissionSummary.demo
    var permissionService: PermissionService = SnapshotPermissionService()
    var errorSummary = ErrorSummary.generic
    var scannedQRCodeValue = ""
    var route = AppRoute.transfer
    var transferServiceForPageModels: TransferService { transferService }
    var transferServiceForTransferView: TransferService { transferService }
    private let transferService: SnapshotTransferService

    init(snapshot: TransferSnapshot) {
        self.transferService = SnapshotTransferService(snapshot: snapshot, completionState: nil)
    }

    func handleResultForPage(_ page: AppRoute, result: PageResult, target: PageTarget?) async {}
    func requestStopTransfer() {}
    func persistSnapshot() {}
    func recordDialogView(name: String) {}
    func recordInteraction(name: String, location: String) {}
}

private actor SnapshotTransferService: TransferService {
    private var snapshot: TransferSnapshot
    private var completionState: TransferCompletionState?

    init(snapshot: TransferSnapshot = .demo, completionState: TransferCompletionState? = nil) {
        self.snapshot = snapshot
        self.completionState = completionState
    }

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
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

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        .skipped
    }
}

private actor SnapshotPermissionService: PermissionService {
    private var isRemoveAfterBackupEnabled = false

    func loadPermissionSummary() async -> PermissionSummary {
        .demo
    }

    func removeAfterBackupEnabled() async -> Bool {
        isRemoveAfterBackupEnabled
    }

    func setRemoveAfterBackupEnabled(_ isEnabled: Bool) async {
        isRemoveAfterBackupEnabled = isEnabled
    }
}
