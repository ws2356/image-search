import Foundation
import Combine

@MainActor
final class HomePageViewModel: ObservableObject {
    private let model: any AppPageModeling
    private let telemetryService: TelemetryService
    @Published private(set) var summary: HomeSummary

    init(model: any AppPageModeling, telemetryService: TelemetryService) {
        self.model = model
        self.telemetryService = telemetryService
        self.summary = model.homeSummary
    }

    func handlePrimaryActionTapped() async {
        telemetryService.recordInteraction(name: "primary_action_tapped", location: "home")
        await model.handleResultForPage(.home, result: .success, target: nil)
    }

    func refreshSummary() async {
        var renderedSummary = model.homeSummary

        if model.backupFlowState == .transferStopped {
            let transferSnapshot = await model.transferServiceForPageModels.progressSnapshot() ?? .demo
            renderedSummary = Self.renderStoppedTransferSummary(
                baseSummary: renderedSummary,
                snapshot: transferSnapshot,
                desktopName: model.pairingStatus.desktopName
            )
        }

        summary = renderedSummary
    }

    private static func renderStoppedTransferSummary(
        baseSummary: HomeSummary,
        snapshot: TransferSnapshot,
        desktopName: String?
    ) -> HomeSummary {
        var renderedSummary = baseSummary
        let totalAttempted = max(
            snapshot.totalCount,
            snapshot.transferredCount + snapshot.failedCount
        )

        if totalAttempted > 0 {
            renderedSummary.lastBackupDescription = "Stopped after \(snapshot.transferredCount) of \(totalAttempted) items."
            renderedSummary.previouslyTransferredDescription = "\(snapshot.transferredCount) items sent in the most recent session."
        } else {
            renderedSummary.lastBackupDescription = "Backup session started, then canceled before any items were sent."
            renderedSummary.previouslyTransferredDescription = "0 items sent in the most recent session."
        }

        renderedSummary.pendingItemCount = nil
        renderedSummary.interruptionWarning = nil
        if let desktopName, !desktopName.isEmpty {
            renderedSummary.desktopName = desktopName
        }
        renderedSummary.detailMessage = "Scan again when you are ready to start another backup session."
        return renderedSummary
    }
}
