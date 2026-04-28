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
        let viewController = makeHostedPage(title: "AuBackup") {
            HomeView(
                summary: .firstLaunch,
                onPrimaryAction: {},
                onScanDesktop: {}
            )
        }
        try SnapshotSupport.assertSnapshot(pageName: "home-new-user", viewController: viewController)
    }

    func test_transfer_in_progress_page() throws {
        let viewController = makeHostedPage(title: "Backup in Progress") {
            TransferSessionView(
                snapshot: .snapshotMarketing,
                onStop: {}
            )
        }
        try SnapshotSupport.assertSnapshot(pageName: "transfer-in-progress", viewController: viewController)
    }

    func test_backup_completion_page() throws {
        let viewController = makeHostedPage(title: "Backup Complete") {
            CompletionStateView(
                summary: .snapshotMarketing,
                onReturnHome: {}
            )
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
        etaDescription: "17 min remaining",
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
