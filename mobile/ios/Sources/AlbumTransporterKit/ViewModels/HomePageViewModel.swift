import Foundation
import Combine

struct HomeViewState: Equatable {
    var desktopName: String?
    var lastBackupDescription: String?
    var previousTransferDescription: String?
    var permissionScope: PermissionScope
    var interruptionWarning: String?

    static let firstLaunch = HomeViewState(
        desktopName: nil,
        lastBackupDescription: nil,
        previousTransferDescription: nil,
        permissionScope: .full,
        interruptionWarning: nil
    )
}

@MainActor
final class HomePageViewModel: ObservableObject {
    private let model: any AppPageModeling
    private let telemetryService: TelemetryService
    @Published private(set) var summary: HomeViewState = .firstLaunch

    init(model: any AppPageModeling, telemetryService: TelemetryService) {
        self.model = model
        self.telemetryService = telemetryService
    }

    func handlePrimaryActionTapped() async {
        telemetryService.recordInteraction(name: "primary_action_tapped", location: "home")
        await model.handleResultForPage(.home, result: .success, target: nil)
    }

    func refreshSummary() async {
        let permissionSummary = await model.permissionService.loadPermissionSummary()
        let backupSession = model.backupSessionProvider.backupSession
        let transferSnapshot = await model.transferServiceForPageModels.progressSnapshot()
        summary = Self.renderSummary(
            backupSession: backupSession,
            transferSnapshot: transferSnapshot,
            permissionScope: permissionSummary.mediaScope,
            backupFlowState: model.backupFlowState,
            pairingStatus: model.pairingStatus
        )
    }

    private static func renderSummary(
        backupSession: BackupSession?,
        transferSnapshot: TransferSnapshot?,
        permissionScope: PermissionScope,
        backupFlowState: MobileBackupFlowState,
        pairingStatus: PairingStatus
    ) -> HomeViewState {
        var summary = HomeViewState(
            desktopName: pairingStatus.desktopName ?? backupSession?.desktopName,
            lastBackupDescription: nil,
            previousTransferDescription: nil,
            permissionScope: permissionScope,
            interruptionWarning: nil
        )

        guard let backupSession else {
            return summary
        }

        switch backupSession.status {
        case .paired:
            summary.lastBackupDescription = "Paired and ready for backup."
        case .completed:
            summary.lastBackupDescription = "Last backup completed just now."
        case .failed:
            summary.lastBackupDescription = "The last backup session ended with failures."
        case .stopped:
            let resolvedTransferSnapshot = transferSnapshot
                ?? TransferSnapshot.empty(transport: pairingStatus.transport ?? .lan, phase: .stopped)
            let totalAttempted = max(
                resolvedTransferSnapshot.totalCount,
                resolvedTransferSnapshot.transferredCount + resolvedTransferSnapshot.failedCount
            )
            if totalAttempted > 0 {
                summary.lastBackupDescription = "Stopped after \(resolvedTransferSnapshot.transferredCount) of \(totalAttempted) items."
                summary.previousTransferDescription = "\(resolvedTransferSnapshot.transferredCount) items sent in the most recent session."
            } else {
                summary.lastBackupDescription = "Backup session started, then canceled before any items were sent."
                summary.previousTransferDescription = "0 items sent in the most recent session."
            }
            if backupFlowState == .transferStopped {
                summary.interruptionWarning = "The previous session stopped before all newly captured media finished transferring."
            }
        }

        return summary
    }
}
