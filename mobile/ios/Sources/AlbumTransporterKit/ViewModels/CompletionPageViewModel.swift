import Foundation
import Combine

@MainActor
final class CompletionPageViewModel: ObservableObject {
    private let model: any AppPageModeling
    @Published private(set) var summary: CompletionSummary = .demo

    init(model: any AppPageModeling) {
        self.model = model
    }

    func reloadSummary() async {
        let transferService = model.transferServiceForPageModels
        let completionState = await transferService.transferCompletionState()
        let snapshot: TransferSnapshot
        if let completedSnapshot = completionState?.snapshot {
            snapshot = completedSnapshot
        } else if let progressSnapshot = await transferService.progressSnapshot() {
            snapshot = progressSnapshot
        } else {
            snapshot = .demo
        }
        let total = max(snapshot.totalCount, snapshot.transferredCount)
        let totalTransferredDescription: String = {
            if snapshot.failedCount > 0 {
                return "\(snapshot.transferredCount)/\(total) (\(snapshot.failedCount) failed)"
            }
            return "\(snapshot.transferredCount)/\(total)"
        }()

        summary = CompletionSummary(
            title: "Backup Complete!",
            message: completionMessage(
                for: snapshot,
                cleanupResult: completionState?.cleanupResult ?? .skipped
            ),
            itemsBackedUp: snapshot.transferredCount,
            totalTransferredDescription: totalTransferredDescription,
            durationDescription: formattedDuration(completionState?.sessionDuration),
            completedAtDescription: formattedCompletionTimestamp(completionState?.completedAt ?? Date())
        )
    }

    func returnHomeTapped() async {
        model.recordInteraction(name: "return_home_tapped", location: "completion")
        await model.handleResultForPage(.completed, result: .success, target: nil)
    }

    private func completionMessage(
        for snapshot: TransferSnapshot,
        cleanupResult: TransferAssetCleanupResult
    ) -> String {
        let baseMessage = "Desktop confirmed \(snapshot.totalCount) eligible items for this session. Media that already transferred may still be indexing on desktop."
        guard model.removeAfterBackupEnabled else {
            return baseMessage
        }
        switch cleanupResult {
        case .skipped:
            return baseMessage
        case .removed(let removedCount):
            let itemLabel = removedCount == 1 ? "item" : "items"
            return "\(baseMessage) Moved \(removedCount) transferred \(itemLabel) to Recently Removed on this device."
        case .failed(let message):
            return "\(baseMessage) Backup succeeded, but moving transferred items to Recently Removed failed: \(message)"
        }
    }

    private func formattedDuration(_ duration: TimeInterval?) -> String {
        guard let duration else {
            return "—"
        }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = [.dropLeading]
        return formatter.string(from: max(duration, 0)) ?? "—"
    }

    private func formattedCompletionTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
