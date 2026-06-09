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
    private var hasReportedMissingProgressSnapshot = false
    private var lastSnapshotDiagnosticSignature: String?
    private static let idleTimerPollingIntervalNanoseconds: UInt64 = 1_000_000_000

    private var transferService: TransferService {
        model.transferService
    }

    @Published private(set) var snapshot: TransferSnapshot
    @Published private(set) var isIncompleteLibrary = false
    @Published var isShowingStopConfirmation = false
    
    static let BATTERY_LEVEL_THRESHOLD_DISABLE_IDLE_TIMER: Float = 0.8

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
        isIncompleteLibrary = await model.permissionService.loadPermissionSummary().mediaScope != .full
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
            stopIdleTimerPolling()
        }

        await startIdleTimerPolling()
        recordSnapshotDiagnosticIfNeeded(area: "transfer_view_loaded", snapshot: snapshot)
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
                        self.hasReportedMissingProgressSnapshot = false
                    }
                    await MainActor.run {
                        self.applySnapshotIfNewer(inFlightSnapshot)
                    }
                } else if !self.hasReportedMissingProgressSnapshot {
                    await MainActor.run {
                        self.hasReportedMissingProgressSnapshot = true
                        self.recordDiagnosticCheckpoint(
                            area: "transfer_poll_snapshot_missing",
                            attributes: [
                                "transfer.poll_interval_ms": .int(Int(self.pollingIntervalNanoseconds / 1_000_000))
                            ]
                        )
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
                try? await Task.sleep(nanoseconds: Self.idleTimerPollingIntervalNanoseconds)
                guard !Task.isCancelled else {
                    return
                }
                await self.refreshIdleTimerPolicy()
            }
        }
    }

    private func stopIdleTimerPolling() {
        idleTimerPollingTask?.cancel()
        idleTimerPollingTask = nil
    }

    private func resolveCleanupResult() async -> TransferAssetCleanupResult {
        guard await model.permissionService.removeAfterBackupEnabled() else {
            return .skipped
        }
        return await transferService.moveSuccessfullyTransferredAssetsToRecentlyRemoved()
    }

    private func applySnapshotIfNewer(_ newSnapshot: TransferSnapshot) {
        snapshot = newSnapshot
        recordSnapshotDiagnosticIfNeeded(area: "transfer_snapshot_applied", snapshot: newSnapshot)
    }

    private func refreshIdleTimerPolicy() async {
        let isCharging = await model.permissionService.loadPermissionSummary().isCharging
        let batteryLevel = batteryLevelProvider.currentBatteryLevel() ?? 0
        idleTimerController.isIdleTimerDisabled = isCharging || batteryLevel > TransferPageViewModel.BATTERY_LEVEL_THRESHOLD_DISABLE_IDLE_TIMER
    }

    private func recordSnapshotDiagnosticIfNeeded(area: String, snapshot: TransferSnapshot) {
        let signature = [
            area,
            snapshot.phase.rawValue,
            snapshot.transport.rawValue,
            String(snapshot.transferredCount),
            String(snapshot.totalCount),
            String(snapshot.failedCount),
            String(snapshot.skippedCount),
            (snapshot.liveTransports ?? []).map(\.rawValue).joined(separator: ",")
        ].joined(separator: "|")
        guard signature != lastSnapshotDiagnosticSignature else {
            return
        }
        lastSnapshotDiagnosticSignature = signature
        recordDiagnosticCheckpoint(
            area: area,
            attributes: [
                "transfer.phase": .string(snapshot.phase.rawValue),
                "transfer.transport": .string(snapshot.transport.rawValue),
                "transfer.transferred_count": .int(snapshot.transferredCount),
                "transfer.total_count": .int(snapshot.totalCount),
                "transfer.failed_count": .int(snapshot.failedCount),
                "transfer.skipped_count": .int(snapshot.skippedCount),
                "transfer.live_transport_count": .int((snapshot.liveTransports ?? []).count),
                "transfer.eta_present": .bool(snapshot.etaMinutes != nil),
                "transfer.failure_message_present": .bool(snapshot.failureMessage?.isEmpty == false)
            ]
        )
    }

    private func recordDiagnosticCheckpoint(
        area: String,
        attributes: MobileTelemetryAttributes = [:]
    ) {
        var diagnosticAttributes = attributes
        diagnosticAttributes["diagnostic.area"] = .string(area)
        diagnosticAttributes["app.route"] = .string(routeName(model.route))
        diagnosticAttributes["backup.flow_state"] = .string(model.backupFlowState.rawValue)
        telemetryService.recordTelemetry(.diagnosticCheckpoint, attributes: diagnosticAttributes)
    }

    private func routeName(_ route: AppRoute) -> String {
        switch route {
        case .home:
            return "home"
        case .scan:
            return "scan"
        case .pair:
            return "pair"
        case .permissions:
            return "permissions"
        case .transfer:
            return "transfer"
        case .completed:
            return "completed"
        case .error:
            return "error"
        }
    }
}
