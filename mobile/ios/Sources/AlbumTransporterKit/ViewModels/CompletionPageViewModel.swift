import Foundation
import Combine

struct CompletionViewState: Equatable {
    var title: String
    var message: String
    var itemsBackedUp: Int?
    var durationDescription: String?
    var completedAtDescription: String?

    static let demo = CompletionViewState(
        title: "Backup Complete!",
        message: "Desktop confirmed this mobile backup session is complete. Already transferred items may still be finishing desktop indexing.",
        itemsBackedUp: nil,
        durationDescription: nil,
        completedAtDescription: nil
    )
}

@MainActor
final class CompletionPageViewModel: ObservableObject {
    private let model: any AppPageModeling
    private let telemetryService: TelemetryService
    @Published private(set) var summary: CompletionViewState = .demo

    init(model: any AppPageModeling, telemetryService: TelemetryService) {
        self.model = model
        self.telemetryService = telemetryService
    }

    func reloadSummary() async {
        let transferService = model.transferService
        let completionState = await transferService.transferCompletionState()
        let snapshot: TransferSnapshot
        if let completedSnapshot = completionState?.snapshot {
            snapshot = completedSnapshot
        } else if let progressSnapshot = await transferService.progressSnapshot() {
            snapshot = progressSnapshot
        } else {
            snapshot = .empty()
        }

        summary = CompletionViewState(
            title: "Backup Complete!",
            message: completionMessage(
                for: snapshot,
                cleanupResult: completionState?.cleanupResult ?? .skipped
            ),
            itemsBackedUp: snapshot.transferredCount,
            durationDescription: formattedDuration(completionState?.sessionDuration),
            completedAtDescription: formattedCompletionTimestamp(completionState?.completedAt ?? Date())
        )
    }

    func returnHomeTapped() async {
        telemetryService.recordInteraction(name: "return_home_tapped", location: "completion")
        let result = CompletionPageResult(result: .success(()))
        await model.onCompletionCompleted(with: result)
    }

    private func completionMessage(
        for snapshot: TransferSnapshot,
        cleanupResult: TransferAssetCleanupResult
    ) -> String {
        let baseMessage = "Desktop confirmed \(snapshot.totalCount) eligible items for this session. Media that already transferred may still be indexing on desktop."
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
