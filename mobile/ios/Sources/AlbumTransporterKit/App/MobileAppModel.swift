import Foundation
#if canImport(UIKit)
import UIKit
#endif
import Combine

@MainActor
final class MobileAppModel: ObservableObject {
    @Published private(set) var route: AppRoute = .home
    @Published private(set) var homeSummary = HomeSummary.firstLaunch
    @Published private(set) var permissionSummary = PermissionSummary.demo
    @Published private(set) var removeAfterBackupEnabled = false
    @Published private(set) var pairingStatus = PairingStatus.idle
    @Published private(set) var transferSnapshot = TransferSnapshot.demo
    @Published private(set) var completionSummary = CompletionSummary.demo
    @Published var scannedQRCodeValue = ""

    @Published var isShowingStopConfirmation = false
    @Published var isShowingLowBatteryWarning = false
    @Published var isShowingMediaAccessAlert = false
    @Published var mediaAccessAlertMessage = "Full Library Access is recommended so Album Transporter can include all local photos and videos."

    private var hasLoaded = false
    private var transferProgressPollingTask: Task<Void, Never>?
    private let transferProgressPollingIntervalNanoseconds: UInt64
    private var transferStartedAt: Date?
    private var isAwaitingMediaAccessDecision = false
    private let stateStore: AppStateStore
    private let qrCodePayloadDecoder: QRCodePayloadDecoding
    private let pairingService: PairingService
    private let permissionService: PermissionService
    private let transferService: TransferService
    private let sideEffectWorker: MobileAppSideEffectWorker
    private var backupFlowStateMachine = MobileBackupFlowStateMachine()
#if canImport(UIKit)
    private var memoryWarningObservationTask: Task<Void, Never>?
#endif

    init(
        stateStore: AppStateStore,
        qrCodePayloadDecoder: QRCodePayloadDecoding,
        pairingService: PairingService,
        permissionService: PermissionService,
        transferService: TransferService,
        telemetryClient: TelemetryClient,
        transferProgressPollingIntervalNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.stateStore = stateStore
        self.qrCodePayloadDecoder = qrCodePayloadDecoder
        self.pairingService = pairingService
        self.permissionService = permissionService
        self.transferService = transferService
        self.sideEffectWorker = MobileAppSideEffectWorker(
            stateStore: stateStore,
            telemetryClient: telemetryClient
        )
        self.transferProgressPollingIntervalNanoseconds = transferProgressPollingIntervalNanoseconds
        configureMemoryWarningObservation()
    }

    deinit {
        transferProgressPollingTask?.cancel()
#if canImport(UIKit)
        memoryWarningObservationTask?.cancel()
#endif
    }

    var navigationTitle: String {
        switch route {
        case .home:
            return "Album Transporter"
        case .scanAndPair:
            return "Scan & Pair"
        case .permissions:
            return "Permissions"
        case .transfer:
            return "Backup in Progress"
        case .completed:
            return "Backup Complete"
        }
    }

    func load() async {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        let snapshot = await stateStore.loadLaunchSnapshot()
        apply(snapshot: snapshot)
        let pairingService = pairingService
        Task.detached(priority: .utility) {
            await pairingService.primeNetworkAccess()
        }
        recordTelemetry(.appLaunched)
    }

    func handleHomePrimaryAction() async {
        switch homeSummary.primaryAction {
        case .scanDesktopQRCode:
            await openScanFlow()
        case .resumeBackup:
            await openScanFlow()
        case .backupPendingItems:
            await startTransfer()
        }
    }

    func openScanFlow() async {
        transitionBackupFlow(.pairingStarted)
        pairingStatus = PairingStatus(
            phase: .scanning,
            desktopName: homeSummary.desktopName,
            sessionID: nil,
            transport: nil,
            message: "Point the camera at the desktop QR code shown in the PC app."
        )
        route = .scanAndPair
        recordTelemetry(.scanStarted)
        persistSnapshot()
    }

    func beginPairing() async {
        transitionBackupFlow(.pairingStarted)
        pairingStatus = PairingStatus(
            phase: .pairing,
            desktopName: homeSummary.desktopName,
            sessionID: nil,
            transport: nil,
            message: "Validating the QR payload and establishing a secure local session with the desktop."
        )
        recordTelemetry(.pairingStarted)

        let payloadResult = qrCodePayloadDecoder.decode(scannedValue: scannedQRCodeValue)

        guard case .success(let payload) = payloadResult else {
            if case .failure(let error) = payloadResult {
                pairingStatus = PairingStatus(
                    phase: .failed,
                    desktopName: homeSummary.desktopName,
                    sessionID: nil,
                    transport: nil,
                    message: error.message
                )
                applyPairingStatusStateTransition(pairingStatus)
            }
            recordTelemetry(.pairingFailed)
            persistSnapshot()
            return
        }

        let result = await pairingService.startPairing(using: payload)
        pairingStatus = result
        applyPairingStatusStateTransition(result)
        persistSnapshot()

        guard result.phase == .paired else {
            recordTelemetry(.pairingFailed)
            return
        }

        homeSummary.desktopName = result.desktopName
        permissionSummary = await permissionService.loadPermissionSummary()
        route = .permissions

        recordTelemetry(.pairingSucceeded)
        persistSnapshot()
    }

    func startBackup() async {
        isShowingMediaAccessAlert = false
        isAwaitingMediaAccessDecision = false
        permissionSummary = await permissionService.loadPermissionSummary()
        guard permissionSummary.mediaScope == .full else {
            mediaAccessAlertMessage = mediaAccessAlertMessage(for: permissionSummary.mediaScope)
            isShowingMediaAccessAlert = true
            isAwaitingMediaAccessDecision = true
            persistSnapshot()
            return
        }

        await beginTransferAfterPreflightChecks()
    }

    func continueBackupWithCurrentMediaAccess() async {
        guard isAwaitingMediaAccessDecision else {
            return
        }
        isAwaitingMediaAccessDecision = false
        isShowingMediaAccessAlert = false
        await beginTransferAfterPreflightChecks()
    }

    func setRemoveAfterBackupEnabled(_ isEnabled: Bool) {
        guard removeAfterBackupEnabled != isEnabled else {
            return
        }
        removeAfterBackupEnabled = isEnabled
        persistSnapshot()
    }

    private func beginTransferAfterPreflightChecks() async {
        if permissionSummary.lowBatteryWarningNeeded && !permissionSummary.isCharging {
            isShowingLowBatteryWarning = true
            persistSnapshot()
            return
        }

        await startTransfer()
    }

    func continuePastLowBatteryWarning() async {
        isShowingLowBatteryWarning = false
        await startTransfer()
    }

    func requestStopTransfer() {
        isShowingStopConfirmation = true
    }

    func confirmStopTransfer() async {
        isShowingStopConfirmation = false
        stopTransferProgressPolling()
        _ = await transferService.stopTransfer(current: transferSnapshot)
        transitionBackupFlow(.transferStopped)
        updateHomeSummaryAfterStoppedTransfer()
        transferStartedAt = nil
        route = .home

        recordTelemetry(.transferStopped)
        persistSnapshot()
    }

    func completeTransfer() async {
        stopTransferProgressPolling()
        transferSnapshot = await transferService.completeTransfer(current: transferSnapshot)
        transitionBackupFlow(transferSnapshot.failedCount == 0 ? .transferCompleted : .transferFailed)
        let cleanupResult: TransferAssetCleanupResult
        if removeAfterBackupEnabled {
            cleanupResult = await transferService.moveSuccessfullyTransferredAssetsToRecentlyRemoved()
        } else {
            cleanupResult = .skipped
        }
        let completedAt = Date()
        let sessionDuration = transferStartedAt.map { completedAt.timeIntervalSince($0) }
        let totalTransferredDescription: String = {
            let total = max(transferSnapshot.totalCount, transferSnapshot.transferredCount)
            if transferSnapshot.failedCount > 0 {
                return "\(transferSnapshot.transferredCount)/\(total) (\(transferSnapshot.failedCount) failed)"
            }
            return "\(transferSnapshot.transferredCount)/\(total)"
        }()
        completionSummary = CompletionSummary(
            title: "Backup Complete!",
            message: completionMessage(for: cleanupResult),
            itemsBackedUp: transferSnapshot.transferredCount,
            totalTransferredDescription: totalTransferredDescription,
            durationDescription: formattedDuration(sessionDuration),
            completedAtDescription: formattedCompletionTimestamp(completedAt)
        )
        homeSummary = .completed(
            desktopName: homeSummary.desktopName,
            permissionScope: permissionSummary.mediaScope,
            lastBackupDescription: "Last backup completed just now."
        )
        transferStartedAt = nil
        route = .completed

        recordTelemetry(.transferCompleted)
        persistSnapshot()
    }

    func returnHome() async {
        stopTransferProgressPolling()
        transferStartedAt = nil
        transitionBackupFlow(.resetToPendingPairing)
        route = .home
        persistSnapshot()
    }

    private func startTransfer() async {
        transferStartedAt = Date()
        transitionBackupFlow(.transferStarted)
        route = .transfer
        transferSnapshot = TransferSnapshot(
            transferredCount: 0,
            totalCount: 0,
            failedCount: 0,
            transport: pairingStatus.transport ?? .lan,
            etaDescription: nil,
            statusMessage: "Preparing the local media backup with the paired desktop.",
            guidanceMessage: "Keep the app in the foreground while the phone sends items to the desktop.",
            isIncompleteLibrary: permissionSummary.mediaScope != .full
        )
        recordTelemetry(.transferStarted)
        persistSnapshot()
        startTransferProgressPolling()
        transferSnapshot = await transferService.startTransfer(progress: { _ in })
        stopTransferProgressPolling()
        guard route == .transfer else {
            persistSnapshot()
            return
        }

        await completeTransfer()
    }

    private func startTransferProgressPolling() {
        stopTransferProgressPolling()
        transferProgressPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }
                if let snapshot = await self.transferService.progressSnapshot() {
                    await MainActor.run {
                        self.transferSnapshot = snapshot
                    }
                }
                try? await Task.sleep(nanoseconds: self.transferProgressPollingIntervalNanoseconds)
            }
        }
    }

    private func stopTransferProgressPolling() {
        transferProgressPollingTask?.cancel()
        transferProgressPollingTask = nil
    }

    private func apply(snapshot: LaunchSnapshot) {
        homeSummary = snapshot.homeSummary
        permissionSummary = snapshot.permissionSummary
        removeAfterBackupEnabled = snapshot.removeAfterBackupEnabled
        pairingStatus = snapshot.pairingStatus
        transferSnapshot = snapshot.transferSnapshot
        backupFlowStateMachine = MobileBackupFlowStateMachine(
            state: inferredBackupFlowState(from: snapshot)
        )
        route = .home
    }

    private func applyPairingStatusStateTransition(_ status: PairingStatus) {
        switch status.phase {
        case .paired:
            transitionBackupFlow(.pairingAccepted)
        case .expired:
            transitionBackupFlow(.pairingFailed)
        case .failed:
            if Self.isPairingMismatchStatusMessage(status.message) {
                transitionBackupFlow(.pairingMismatchDetected)
            } else {
                transitionBackupFlow(.pairingFailed)
            }
        case .instructions, .scanning, .pairing:
            transitionBackupFlow(.pairingStarted)
        }
    }

    private func transitionBackupFlow(_ event: MobileBackupFlowEvent) {
        backupFlowStateMachine.transition(event)
    }

    private func inferredBackupFlowState(from snapshot: LaunchSnapshot) -> MobileBackupFlowState {
        switch snapshot.homeSummary.primaryAction {
        case .backupPendingItems:
            return .pairingCompleted
        case .scanDesktopQRCode, .resumeBackup:
            break
        }
        return snapshot.pairingStatus.phase == .paired ? .pairingCompleted : .pendingPairing
    }

    private static func isPairingMismatchStatusMessage(_ message: String) -> Bool {
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedMessage.isEmpty else {
            return false
        }
        return normalizedMessage.contains("no longer paired") || normalizedMessage.contains("mismatch")
    }

    private func persistSnapshot() {
        let snapshot = LaunchSnapshot(
            homeSummary: homeSummary,
            permissionSummary: permissionSummary,
            pairingStatus: pairingStatus,
            transferSnapshot: transferSnapshot,
            removeAfterBackupEnabled: removeAfterBackupEnabled
        )
        let worker = sideEffectWorker
        Task.detached(priority: .utility) {
            await worker.persist(snapshot: snapshot)
        }
    }

    private func recordTelemetry(_ event: MobileTelemetryEvent) {
        let worker = sideEffectWorker
        Task.detached(priority: .utility) {
            await worker.record(event: event)
        }
    }

    private func configureMemoryWarningObservation() {
#if canImport(UIKit)
        memoryWarningObservationTask?.cancel()
        memoryWarningObservationTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UIApplication.didReceiveMemoryWarningNotification
            ) {
                guard let self else {
                    return
                }
                await self.handleMemoryWarningNotification()
            }
        }
#endif
    }

    private func handleMemoryWarningNotification() {
        recordTelemetry(.memoryWarningReceived)
        let transferService = transferService
        Task.detached(priority: .utility) {
            await transferService.handleMemoryWarning()
        }
    }

    private func mediaAccessAlertMessage(for scope: PermissionScope) -> String {
        switch scope {
        case .full:
            return "Album Transporter already has Full Library Access."
        case .limited:
            return "Full Library Access is recommended so Album Transporter can include your complete library. You can continue now, or open Settings to upgrade Photos access."
        case .photosOnly, .videosOnly, .denied:
            return "Full Library Access is recommended so Album Transporter can include all local photos and videos. You can continue now, or open Settings to grant broader access."
        }
    }

    private func completionMessage(for cleanupResult: TransferAssetCleanupResult) -> String {
        let baseMessage = "Desktop confirmed \(transferSnapshot.totalCount) eligible items for this session. Media that already transferred may still be indexing on desktop."
        guard removeAfterBackupEnabled else {
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

    private func updateHomeSummaryAfterStoppedTransfer() {
        let totalAttempted = max(
            transferSnapshot.totalCount,
            transferSnapshot.transferredCount + transferSnapshot.failedCount
        )

        if totalAttempted > 0 {
            homeSummary.lastBackupDescription = "Stopped after \(transferSnapshot.transferredCount) of \(totalAttempted) items."
            homeSummary.previouslyTransferredDescription = "\(transferSnapshot.transferredCount) items sent in the most recent session."
        } else {
            homeSummary.lastBackupDescription = "Backup session started, then canceled before any items were sent."
            homeSummary.previouslyTransferredDescription = "0 items sent in the most recent session."
        }

        homeSummary.primaryAction = .scanDesktopQRCode
        homeSummary.pendingItemCount = nil
        homeSummary.interruptionWarning = nil
        if let desktopName = pairingStatus.desktopName, !desktopName.isEmpty {
            homeSummary.desktopName = desktopName
        }
        homeSummary.detailMessage = "Scan again when you are ready to start another backup session."
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

actor MobileAppSideEffectWorker {
    private let stateStore: AppStateStore
    private let telemetryClient: TelemetryClient

    init(stateStore: AppStateStore, telemetryClient: TelemetryClient) {
        self.stateStore = stateStore
        self.telemetryClient = telemetryClient
    }

    func persist(snapshot: LaunchSnapshot) async {
        await stateStore.saveLaunchSnapshot(snapshot)
    }

    func record(event: MobileTelemetryEvent) async {
        await telemetryClient.record(event: event)
    }
}
