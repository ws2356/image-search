import SwiftUI
import Combine

@MainActor
final class TransferPageViewModel: ObservableObject {
    private let model: any TransferPageModeling
    private let pollingIntervalNanoseconds: UInt64
    private var modelChangeCancellable: AnyCancellable?
    private var transferPollingTask: Task<Void, Never>?
    private var hasStartedTransferOrchestration = false

    @Published private(set) var snapshot: TransferSnapshot
    @Published var isShowingStopConfirmation = false

    init(
        model: any TransferPageModeling,
        pollingIntervalNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.model = model
        self.pollingIntervalNanoseconds = pollingIntervalNanoseconds
        self.snapshot = .demo
        if let observableModel = model as? MobileAppModel {
            modelChangeCancellable = observableModel.objectWillChange.sink { [weak self] _ in
                self?.objectWillChange.send()
            }
        }
        Task { [weak self] in
            await self?.loadStagedSnapshot()
        }
    }

    var isShowingStopConfirmationBinding: Binding<Bool> {
        Binding(
            get: { self.isShowingStopConfirmation },
            set: { self.isShowingStopConfirmation = $0 }
        )
    }

    func requestStopTransfer() {
        model.recordInteraction(name: "stop_backup_tapped", location: "transfer")
        model.requestStopTransfer()
        isShowingStopConfirmation = true
    }

    func recordStopConfirmationPresented() {
        model.recordDialogView(name: "stop_confirmation")
    }

    func confirmStopTransfer() async {
        model.recordInteraction(name: "stop_confirmed", location: "stop_confirmation")
        isShowingStopConfirmation = false
        let currentSnapshot = await model.transferServiceForTransferView.progressSnapshot() ?? snapshot
        _ = await model.transferServiceForTransferView.stopTransfer(current: currentSnapshot)
        await model.transferServiceForTransferView.stageTransferSnapshot(currentSnapshot)
        snapshot = currentSnapshot
        await model.handleResultForPage(.transfer, result: .failure, target: .stopTransferConfirmed)
    }

    func orchestrateTransfer() async {
        guard !hasStartedTransferOrchestration else {
            return
        }
        hasStartedTransferOrchestration = true
        defer {
            hasStartedTransferOrchestration = false
            stopTransferPolling()
        }

        if let stagedSnapshot = await model.transferServiceForTransferView.progressSnapshot() {
            applySnapshotIfNewer(stagedSnapshot)
        }
        await model.transferServiceForTransferView.stageTransferCompletionState(nil)
        let transferStartedAt = Date()
        startTransferPolling()
        let finalSnapshot = await model.transferServiceForTransferView.startTransfer { _ in }
        applySnapshotIfNewer(finalSnapshot)
        guard model.route == .transfer else {
            model.persistSnapshot()
            return
        }

        let completedSnapshot = await model.transferServiceForTransferView.completeTransfer(current: snapshot)
        applySnapshotIfNewer(completedSnapshot)
        let resolvedCleanupResult: TransferAssetCleanupResult
        if model.removeAfterBackupEnabled {
            resolvedCleanupResult = await model.transferServiceForTransferView.moveSuccessfullyTransferredAssetsToRecentlyRemoved()
        } else {
            resolvedCleanupResult = .skipped
        }
        await model.transferServiceForTransferView.stageTransferCompletionState(
            TransferCompletionState(
                snapshot: snapshot,
                cleanupResult: resolvedCleanupResult,
                completedAt: Date(),
                sessionDuration: Date().timeIntervalSince(transferStartedAt)
            )
        )
        await model.transferServiceForTransferView.stageTransferSnapshot(snapshot)
        await model.handleResultForPage(.transfer, result: .success, target: .secondary)
    }

    func keepBackingUp() {
        model.recordInteraction(name: "stop_cancelled", location: "stop_confirmation")
        isShowingStopConfirmation = false
    }

    private func startTransferPolling() {
        stopTransferPolling()
        let interval = pollingIntervalNanoseconds
        transferPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                if let inFlightSnapshot = await model.transferServiceForTransferView.progressSnapshot() {
                    await MainActor.run {
                        self.applySnapshotIfNewer(inFlightSnapshot)
                    }
                }
                try? await Task.sleep(nanoseconds: interval)
            }
        }
    }

    private func stopTransferPolling() {
        transferPollingTask?.cancel()
        transferPollingTask = nil
    }

    private func applySnapshotIfNewer(_ newSnapshot: TransferSnapshot) {
        guard
            newSnapshot.totalCount != snapshot.totalCount
                || newSnapshot.transferredCount >= snapshot.transferredCount
        else {
            return
        }
        snapshot = newSnapshot
    }

    private func loadStagedSnapshot() async {
        guard let stagedSnapshot = await model.transferServiceForTransferView.progressSnapshot() else {
            return
        }
        applySnapshotIfNewer(stagedSnapshot)
    }
}
