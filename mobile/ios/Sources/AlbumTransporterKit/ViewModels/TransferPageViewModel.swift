import SwiftUI

@MainActor
final class TransferPageViewModel: ObservableObject {
    private let model: any TransferPageModeling
    private let transportResolver: AppTransferTransportResolving
    private let telemetryService: TelemetryService
    private let idleTimerController: any IdleTimerControlling
    private let batteryLevelProvider: any BatteryLevelProviding
    private let pollingIntervalNanoseconds: UInt64
    private var transferPollingTask: Task<Void, Never>?
    private var idleTimerPollingTask: Task<Void, Never>?
    private var hasStartedTransferOrchestration = false
    private static let idleTimerPollingIntervalNanoseconds: UInt64 = 1_000_000_000

    private var transferService: TransferService {
        model.transferService
    }

    @Published private(set) var snapshot: TransferSnapshot
    @Published private(set) var isIncompleteLibrary = false
    @Published var isShowingStopConfirmation = false

    init(
        model: any TransferPageModeling,
        telemetryService: TelemetryService,
        transportResolver: AppTransferTransportResolving,
        idleTimerController: any IdleTimerControlling = ApplicationIdleTimerController(),
        batteryLevelProvider: any BatteryLevelProviding = DeviceBatteryLevelProvider(),
        pollingIntervalNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.model = model
        self.transportResolver = transportResolver
        self.telemetryService = telemetryService
        self.idleTimerController = idleTimerController
        self.batteryLevelProvider = batteryLevelProvider
        self.pollingIntervalNanoseconds = pollingIntervalNanoseconds
        let initialSnapshot = TransferSnapshot.empty(transport: .lan)
        self.snapshot = initialSnapshot
    }

    func loadFromViewLifecycle() async {
        await loadStagedSnapshot()
        await startIdleTimerPolling()
    }

    func handleViewDidDisappear() {
        stopIdleTimerPolling()
        idleTimerController.isIdleTimerDisabled = false
    }

    var isShowingStopConfirmationBinding: Binding<Bool> {
        Binding(
            get: { self.isShowingStopConfirmation },
            set: { self.isShowingStopConfirmation = $0 }
        )
    }

    func requestStopTransfer() {
        telemetryService.recordInteraction(name: "stop_backup_tapped", location: "transfer")
        isShowingStopConfirmation = true
    }

    func recordStopConfirmationPresented() {
        telemetryService.recordDialogView(name: "stop_confirmation")
    }

    func confirmStopTransfer() async {
        telemetryService.recordInteraction(name: "stop_confirmed", location: "stop_confirmation")
        isShowingStopConfirmation = false
        let currentSnapshot = await transferService.progressSnapshot() ?? snapshot
        _ = await transferService.stopTransfer()
        snapshot = currentSnapshot
        let result = TransferPageResult(result: .failure(.stopConfirmed), target: .stopTransferConfirmed)
        await model.onTransferCompleted(with: result)
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
        startTransferPolling()
        // DO NOT use this callback to update UI, use polling instead.
        let finalSnapshot = await transferService.startTransfer { _ in }
        applySnapshotIfNewer(finalSnapshot)
        guard model.route == .transfer else {
            return
        }

        let completedSnapshot = await transferService.completeTransfer()
        applySnapshotIfNewer(completedSnapshot)
        _ = await resolveCleanupResult()
        let result = TransferPageResult(result: .success(()), target: nil)
        await model.onTransferCompleted(with: result)
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
                let sleepInterval: UInt64
                if self.snapshot.totalCount == 0, self.snapshot.transferredCount == 0 {
                    sleepInterval = min(interval, 10_000_000)
                } else {
                    sleepInterval = interval
                }
                try? await Task.sleep(nanoseconds: sleepInterval)
            }
        }
    }

    private func stopTransferPolling() {
        transferPollingTask?.cancel()
        transferPollingTask = nil
    }

    private func startIdleTimerPolling() async {
        stopIdleTimerPolling()
        await refreshIdleTimerPolicy()
        idleTimerPollingTask = Task { [weak self] in
            guard let self else {
                return
            }
            while !Task.isCancelled {
                await self.refreshIdleTimerPolicy()
                try? await Task.sleep(nanoseconds: Self.idleTimerPollingIntervalNanoseconds)
            }
        }
    }

    private func stopIdleTimerPolling() {
        idleTimerPollingTask?.cancel()
        idleTimerPollingTask = nil
    }

    private func loadCurrentSnapshot() async {
        guard let stagedSnapshot = await transferService.progressSnapshot() else {
            let fallbackTransport = await transportResolver.currentTransport() ?? .lan
            snapshot = .empty(transport: fallbackTransport)
            isIncompleteLibrary = await model.permissionService.loadPermissionSummary().mediaScope != .full
            return
        }
        isIncompleteLibrary = await model.permissionService.loadPermissionSummary().mediaScope != .full
        applySnapshotIfNewer(stagedSnapshot)
    }

    private func resolveCleanupResult() async -> TransferAssetCleanupResult {
        guard await model.permissionService.removeAfterBackupEnabled() else {
            return .skipped
        }
        return await transferService.moveSuccessfullyTransferredAssetsToRecentlyRemoved()
    }

    private func applySnapshotIfNewer(_ newSnapshot: TransferSnapshot) {
        let currentSnapshot = snapshot
        guard
            newSnapshot.totalCount != currentSnapshot.totalCount
                || newSnapshot.transferredCount >= currentSnapshot.transferredCount
        else {
            return
        }
        snapshot = newSnapshot
    }

    private func loadStagedSnapshot() async {
        await loadCurrentSnapshot()
    }

    private func refreshIdleTimerPolicy() async {
        let usbTransportAlive = await transferService.isUSBTransportAlive()
        let batteryLevel = batteryLevelProvider.currentBatteryLevel() ?? 0
        idleTimerController.isIdleTimerDisabled = usbTransportAlive || batteryLevel > 0.9
    }
}
