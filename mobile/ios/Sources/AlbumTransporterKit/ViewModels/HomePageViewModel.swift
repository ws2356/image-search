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
    private let transportResolver: AppTransferTransportResolving
    private let telemetryService: TelemetryService
    @Published private(set) var summary: HomeViewState = .firstLaunch
    private var backupSessionObserver: AnyCancellable?

    init(
        model: any AppPageModeling,
        telemetryService: TelemetryService,
        transportResolver: AppTransferTransportResolving
    ) {
        self.model = model
        self.telemetryService = telemetryService
        self.transportResolver = transportResolver
        self.backupSessionObserver = model.backupSessionProvider.lastBackupSessionPublisher
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.refreshSummary() }
            }
    }

    func handlePrimaryActionTapped() async {
        telemetryService.recordInteraction(name: "primary_action_tapped", location: "home")
        let result = HomePageResult(result: .success(()))
        await model.onHomeCompleted(with: result)
    }

    func refreshSummary() async {
        let permissionSummary = await model.permissionService.loadPermissionSummary()
        let backupSession = model.backupSessionProvider.lastBackupSession
        let transferSnapshot = await model.transferService.progressSnapshot()
        let fallbackTransport = await transportResolver.currentTransport() ?? .lan
        let renderedSummary = Self.renderSummary(
            backupSession: backupSession,
            transferSnapshot: transferSnapshot,
            permissionScope: permissionSummary.mediaScope,
            backupFlowState: model.backupFlowState,
            fallbackTransport: fallbackTransport
        )
        summary = renderedSummary
        telemetryService.recordTelemetry(
            .diagnosticCheckpoint,
            attributes: Self.summaryDiagnosticAttributes(
                summary: renderedSummary,
                backupSession: backupSession,
                transferSnapshot: transferSnapshot,
                permissionScope: permissionSummary.mediaScope,
                backupFlowState: model.backupFlowState,
                fallbackTransport: fallbackTransport
            )
        )
    }

    private static func renderSummary(
        backupSession: BackupSession?,
        transferSnapshot: TransferSnapshot?,
        permissionScope: PermissionScope,
        backupFlowState: MobileBackupFlowState,
        fallbackTransport: TransferTransport
    ) -> HomeViewState {
        var summary = HomeViewState(
            desktopName: backupSession?.desktopName,
            lastBackupDescription: nil,
            previousTransferDescription: nil,
            permissionScope: permissionScope,
            interruptionWarning: nil
        )

        guard let backupSession else {
            return summary
        }

        switch backupSession.status {
        case .pairingCompleted, .transferInProgress:
            summary.lastBackupDescription = "Paired and ready for backup."
        case .transferCompleted:
            summary.lastBackupDescription = "Last backup completed just now."
        case .pairingFailed, .transferFailed:
            summary.lastBackupDescription = "The last backup session ended with failures."
        case .pairingStopped, .transferStopped:
            let resolvedTransferSnapshot = transferSnapshot
                ?? TransferSnapshot.empty(transport: fallbackTransport, phase: .stopped)
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
        case .pendingPairing, .pairingMismatched, .pairingExpired:
            break
        }

        return summary
    }

    private static func summaryDiagnosticAttributes(
        summary: HomeViewState,
        backupSession: BackupSession?,
        transferSnapshot: TransferSnapshot?,
        permissionScope: PermissionScope,
        backupFlowState: MobileBackupFlowState,
        fallbackTransport: TransferTransport
    ) -> MobileTelemetryAttributes {
        var attributes: MobileTelemetryAttributes = [
            "diagnostic.area": .string("home_summary_refreshed"),
            "home.permission_scope": .string(permissionScope.rawValue),
            "home.has_session_history": .bool(summary.lastBackupDescription != nil),
            "home.has_previous_transfer_description": .bool(summary.previousTransferDescription != nil),
            "home.has_interruption_warning": .bool(summary.interruptionWarning != nil),
            "backup.flow_state": .string(backupFlowState.rawValue),
            "transfer.fallback_transport": .string(fallbackTransport.rawValue),
            "backup.session_present": .bool(backupSession != nil)
        ]
        if let backupSession {
            attributes["backup.session_status"] = .string(backupSession.status.rawValue)
            attributes["backup.session_id_present"] = .bool(backupSession.sessionID?.isEmpty == false)
            attributes["backup.desktop_name_present"] = .bool(!(backupSession.desktopName ?? "").isEmpty)
        }
        if let transferSnapshot {
            attributes["transfer.snapshot_present"] = .bool(true)
            attributes["transfer.phase"] = .string(transferSnapshot.phase.rawValue)
            attributes["transfer.transferred_count"] = .int(transferSnapshot.transferredCount)
            attributes["transfer.total_count"] = .int(transferSnapshot.totalCount)
            attributes["transfer.failed_count"] = .int(transferSnapshot.failedCount)
            attributes["transfer.skipped_count"] = .int(transferSnapshot.skippedCount)
            attributes["transfer.transport"] = .string(transferSnapshot.transport.rawValue)
        } else {
            attributes["transfer.snapshot_present"] = .bool(false)
        }
        return attributes
    }
}
