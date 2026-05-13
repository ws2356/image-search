import SwiftUI

@MainActor
final class TransferPageViewModel: ObservableObject {
    private let model: any TransferPageModeling
    private let telemetryService: TelemetryService
    private let pollingIntervalNanoseconds: UInt64
    private var transferPollingTask: Task<Void, Never>?
    private var hasStartedTransferOrchestration = false

    private var transferService: TransferService {
        model.transferServiceForTransferView
    }

    @Published private(set) var snapshot: TransferSnapshot
    @Published var isShowingStopConfirmation = false

    init(
        model: any TransferPageModeling,
        telemetryService: TelemetryService,
        pollingIntervalNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.model = model
        self.telemetryService = telemetryService
        self.pollingIntervalNanoseconds = pollingIntervalNanoseconds
        self.snapshot = TransferSnapshot(
            transferredCount: 0,
            totalCount: 0,
            failedCount: 0,
            transport: model.pairingStatus.transport ?? .lan,
            etaMinutes: nil,
            statusMessage: "Preparing the local media backup with the paired desktop.",
            guidanceMessage: "Keep the app in the foreground while the phone sends items to the desktop.",
            isIncompleteLibrary: model.permissionSummary.mediaScope != .full
        )
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
        telemetryService.recordInteraction(name: "stop_backup_tapped", location: "transfer")
        model.requestStopTransfer()
        isShowingStopConfirmation = true
    }

    func recordStopConfirmationPresented() {
        telemetryService.recordDialogView(name: "stop_confirmation")
    }

    func confirmStopTransfer() async {
        telemetryService.recordInteraction(name: "stop_confirmed", location: "stop_confirmation")
        isShowingStopConfirmation = false
        let currentSnapshot = await transferService.progressSnapshot() ?? snapshot
        _ = await transferService.stopTransfer(current: currentSnapshot)
        await transferService.stageTransferSnapshot(currentSnapshot)
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

        await loadCurrentSnapshot()
        await transferService.stageTransferCompletionState(nil)
        let transferStartedAt = Date()
        startTransferPolling()
        let finalSnapshot = await transferService.startTransfer { _ in }
        applySnapshotIfNewer(finalSnapshot)
        guard model.route == .transfer else {
            model.persistSnapshot()
            return
        }

        let completedSnapshot = await transferService.completeTransfer(current: snapshot)
        applySnapshotIfNewer(completedSnapshot)
        let resolvedCleanupResult = await resolveCleanupResult()
        await transferService.stageTransferCompletionState(
            TransferCompletionState(
                snapshot: snapshot,
                cleanupResult: resolvedCleanupResult,
                completedAt: Date(),
                sessionDuration: Date().timeIntervalSince(transferStartedAt)
            )
        )
        await transferService.stageTransferSnapshot(snapshot)
        await model.handleResultForPage(.transfer, result: .success, target: .secondary)
    }

    func keepBackingUp() {
        telemetryService.recordInteraction(name: "stop_cancelled", location: "stop_confirmation")
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
                if let inFlightSnapshot = await transferService.progressSnapshot() {
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

    private func loadCurrentSnapshot() async {
        guard let stagedSnapshot = await transferService.progressSnapshot() else {
            return
        }
        applySnapshotIfNewer(stagedSnapshot)
    }

    private func resolveCleanupResult() async -> TransferAssetCleanupResult {
        guard await model.permissionService.removeAfterBackupEnabled() else {
            return .skipped
        }
        return await transferService.moveSuccessfullyTransferredAssetsToRecentlyRemoved()
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
        await loadCurrentSnapshot()
    }
}
