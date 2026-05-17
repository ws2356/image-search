import SwiftUI
import UIKit
import Combine
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
            backupSession: nil,
            permissionSummary: .allClear,
            completionState: nil,
            route: .home,
            backupFlowState: .pendingPairing,
            pairingStatus: .idle
        )
        let telemetryService = SnapshotTelemetryService()
        let viewController = makeHostedPage(title: "AuBackup") {
            HomeView(
                viewModel: HomePageViewModel(
                    model: homeModel,
                    telemetryService: telemetryService
                )
            )
        }
        try SnapshotSupport.assertSnapshot(pageName: "home-new-user", viewController: viewController)
    }

    func test_transfer_in_progress_page() throws {
        let transferModel = SnapshotTransferPageModel(snapshot: .snapshotMarketing)
        let telemetryService = SnapshotTelemetryService()
        let transferViewModel = TransferPageViewModel(
            model: transferModel,
            telemetryService: telemetryService
        )
        let loadedExpectation = expectation(description: "transfer snapshot loaded")
        Task { @MainActor in
            await transferViewModel.orchestrateTransfer()
            loadedExpectation.fulfill()
        }
        wait(for: [loadedExpectation], timeout: 1.0)
        let viewController = makeHostedPage(title: "Backup in Progress") {
            TransferSessionView(
                viewModel: transferViewModel
            )
        }
        try SnapshotSupport.assertSnapshot(pageName: "transfer-in-progress", viewController: viewController)
    }

    func test_backup_completion_page() throws {
        let completedSnapshot = TransferSnapshot(
            transferredCount: 930,
            totalCount: 930,
            failedCount: 0,
            skippedCount: 24,
            transport: .usb,
            liveTransports: [.usb, .lan],
            etaMinutes: nil,
            phase: .completed
        )
        let completionModel = SnapshotAppPageModel(
            backupSession: BackupSession(
                sessionID: "snapshot-session",
                desktopName: "Desk Mac",
                status: .completed,
                updatedAt: Date()
            ),
            permissionSummary: .allClear,
            completionState: TransferCompletionState(
                snapshot: completedSnapshot,
                cleanupResult: .skipped,
                completedAt: Date(),
                sessionDuration: 24 * 60
            ),
            route: .completed,
            backupFlowState: .transferCompleted,
            pairingStatus: PairingStatus(
                phase: .paired,
                backupFlowState: .transferCompleted,
                desktopName: "Desk Mac",
                sessionID: "snapshot-session",
                transport: .usb
            )
        )
        let telemetryService = SnapshotTelemetryService()
        let completionViewModel = CompletionPageViewModel(
            model: completionModel,
            telemetryService: telemetryService
        )
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
        skippedCount: 21,
        transport: .usb,
        liveTransports: [.usb, .lan],
        transferSpeedBytesPerSecond: 42.8 * 1_048_576.0,
        etaMinutes: 17,
        phase: .transferring
    )
}

@MainActor
private final class SnapshotBackupSessionProvider: BackupSessionProviding {
    private let subject: CurrentValueSubject<BackupSession?, Never>

    init(session: BackupSession?) {
        subject = CurrentValueSubject(session)
    }

    var backupSession: BackupSession? {
        subject.value
    }

    var backupSessionPublisher: AnyPublisher<BackupSession?, Never> {
        subject.eraseToAnyPublisher()
    }

    func load() async {}

    func saveBackupSession(_ session: BackupSession?) async {
        subject.send(session)
    }
}

@MainActor
private final class SnapshotAppPageModel: AppPageModeling {
    let backupSessionProvider: BackupSessionProviding
    var backupFlowState: MobileBackupFlowState
    var pairingStatus: PairingStatus
    var permissionService: PermissionService
    var errorSummary = ErrorSummary.generic
    var route: AppRoute
    let transferService: TransferService

    init(
        backupSession: BackupSession?,
        permissionSummary: PermissionSummary,
        completionState: TransferCompletionState?,
        route: AppRoute,
        backupFlowState: MobileBackupFlowState,
        pairingStatus: PairingStatus
    ) {
        backupSessionProvider = SnapshotBackupSessionProvider(session: backupSession)
        permissionService = SnapshotPermissionService(summary: permissionSummary)
        self.route = route
        self.backupFlowState = backupFlowState
        self.pairingStatus = pairingStatus
        let snapshot = completionState?.snapshot ?? .empty(transport: pairingStatus.transport ?? .lan)
        self.transferService = SnapshotTransferService(
            snapshot: snapshot,
            completionState: completionState
        )
    }

    func requestStopTransfer() {}
    func onHomeCompleted(with result: HomePageResult) async {}
    func onScanningCompleted(with result: ScanningPageResult) async {}
    func onPairingCompleted(with result: PairingPageResult) async {}
    func onPermissionsCompleted(with result: PermissionsPageResult) async {}
    func onTransferCompleted(with result: TransferPageResult) async {}
    func onCompletionCompleted(with result: CompletionPageResult) async {}
    func onErrorCompleted(with result: ErrorPageResult) async {}
}

@MainActor
private final class SnapshotTransferPageModel: TransferPageModeling {
    let backupSessionProvider: BackupSessionProviding
    var backupFlowState: MobileBackupFlowState = .transferInProgress
    var pairingStatus: PairingStatus
    var permissionService: PermissionService
    var errorSummary = ErrorSummary.generic
    var route = AppRoute.transfer
    let transferService: TransferService

    init(snapshot: TransferSnapshot) {
        backupSessionProvider = SnapshotBackupSessionProvider(
            session: BackupSession(
                sessionID: "snapshot-session",
                desktopName: "Desk Mac",
                status: .paired,
                updatedAt: Date()
            )
        )
        permissionService = SnapshotPermissionService(summary: .allClear)
        pairingStatus = PairingStatus(
            phase: .paired,
            backupFlowState: .transferInProgress,
            desktopName: "Desk Mac",
            sessionID: "snapshot-session",
            transport: snapshot.transport
        )
        self.transferService = SnapshotTransferService(snapshot: snapshot, completionState: nil)
    }

    func requestStopTransfer() {}
    func onHomeCompleted(with result: HomePageResult) async {}
    func onScanningCompleted(with result: ScanningPageResult) async {}
    func onPairingCompleted(with result: PairingPageResult) async {}
    func onPermissionsCompleted(with result: PermissionsPageResult) async {}
    func onTransferCompleted(with result: TransferPageResult) async {}
    func onCompletionCompleted(with result: CompletionPageResult) async {}
    func onErrorCompleted(with result: ErrorPageResult) async {}
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
        self.snapshot = snapshot
        progress(snapshot)
        return snapshot
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
    private let summary: PermissionSummary
    private var isRemoveAfterBackupEnabled = false

    init(summary: PermissionSummary = .demo) {
        self.summary = summary
    }

    func loadPermissionSummary() async -> PermissionSummary {
        summary
    }

    func removeAfterBackupEnabled() async -> Bool {
        isRemoveAfterBackupEnabled
    }

    func setRemoveAfterBackupEnabled(_ isEnabled: Bool) async {
        isRemoveAfterBackupEnabled = isEnabled
    }
}
@MainActor
private final class SnapshotTelemetryService: TelemetryService {
    func recordTelemetry(_ event: MobileTelemetryEvent, attributes: MobileTelemetryAttributes) {}
    func beginTelemetrySpan(_ span: MobileTelemetrySpan, attributes: MobileTelemetryAttributes) {}
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
