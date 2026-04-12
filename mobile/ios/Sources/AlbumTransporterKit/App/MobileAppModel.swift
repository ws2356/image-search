import Foundation
import Observation

@Observable
@MainActor
final class MobileAppModel {
    private(set) var route: AppRoute = .home
    private(set) var homeSummary = HomeSummary.firstLaunch
    private(set) var permissionSummary = PermissionSummary.demo
    private(set) var pairingStatus = PairingStatus.idle
    private(set) var transferSnapshot = TransferSnapshot.demo
    private(set) var completionSummary = CompletionSummary.demo
    var scannedQRCodeValue = ""

    var isShowingStopConfirmation = false
    var isShowingLowBatteryWarning = false
    var isShowingMediaAccessAlert = false
    var mediaAccessAlertMessage = "Full Library Access is recommended so Album Transporter can include all local photos and videos."

    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var transferProgressPollingTask: Task<Void, Never>?
    @ObservationIgnored private let transferProgressPollingInterval: Duration
    @ObservationIgnored private var transferStartedAt: Date?
    @ObservationIgnored private var isAwaitingMediaAccessDecision = false
    @ObservationIgnored private let stateStore: AppStateStore
    @ObservationIgnored private let qrCodePayloadDecoder: QRCodePayloadDecoding
    @ObservationIgnored private let pairingService: PairingService
    @ObservationIgnored private let permissionService: PermissionService
    @ObservationIgnored private let transferService: TransferService
    @ObservationIgnored private let telemetryClient: TelemetryClient

    init(
        stateStore: AppStateStore,
        qrCodePayloadDecoder: QRCodePayloadDecoding,
        pairingService: PairingService,
        permissionService: PermissionService,
        transferService: TransferService,
        telemetryClient: TelemetryClient,
        transferProgressPollingInterval: Duration = .seconds(2)
    ) {
        self.stateStore = stateStore
        self.qrCodePayloadDecoder = qrCodePayloadDecoder
        self.pairingService = pairingService
        self.permissionService = permissionService
        self.transferService = transferService
        self.telemetryClient = telemetryClient
        self.transferProgressPollingInterval = transferProgressPollingInterval
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
        await telemetryClient.record(event: .appLaunched)
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
        pairingStatus = PairingStatus(
            phase: .scanning,
            desktopName: homeSummary.desktopName,
            sessionID: nil,
            transport: nil,
            message: "Point the camera at the desktop QR code shown in the PC app."
        )
        route = .scanAndPair
        await telemetryClient.record(event: .scanStarted)
        await persistSnapshot()
    }

    func beginPairing() async {
        pairingStatus = PairingStatus(
            phase: .pairing,
            desktopName: homeSummary.desktopName,
            sessionID: nil,
            transport: nil,
            message: "Validating the QR payload and establishing a secure local session with the desktop."
        )
        await telemetryClient.record(event: .pairingStarted)

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
            }
            await telemetryClient.record(event: .pairingFailed)
            await persistSnapshot()
            return
        }

        let result = await pairingService.startPairing(using: payload)
        pairingStatus = result
        await persistSnapshot()

        guard result.phase == .paired else {
            await telemetryClient.record(event: .pairingFailed)
            return
        }

        homeSummary.desktopName = result.desktopName
        permissionSummary = await permissionService.loadPermissionSummary()
        route = .permissions

        await telemetryClient.record(event: .pairingSucceeded)
        await persistSnapshot()
    }

    func startBackup() async {
        isShowingMediaAccessAlert = false
        isAwaitingMediaAccessDecision = false
        permissionSummary = await permissionService.loadPermissionSummary()
        guard permissionSummary.mediaScope == .full else {
            mediaAccessAlertMessage = mediaAccessAlertMessage(for: permissionSummary.mediaScope)
            isShowingMediaAccessAlert = true
            isAwaitingMediaAccessDecision = true
            await persistSnapshot()
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

    private func beginTransferAfterPreflightChecks() async {
        if permissionSummary.lowBatteryWarningNeeded && !permissionSummary.isCharging {
            isShowingLowBatteryWarning = true
            await persistSnapshot()
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
        updateHomeSummaryAfterStoppedTransfer()
        transferStartedAt = nil
        route = .home

        await telemetryClient.record(event: .transferStopped)
        await persistSnapshot()
    }

    func completeTransfer() async {
        stopTransferProgressPolling()
        transferSnapshot = await transferService.completeTransfer(current: transferSnapshot)
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
            message: "Desktop confirmed \(transferSnapshot.totalCount) eligible items for this session. Media that already transferred may still be indexing on desktop.",
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

        await telemetryClient.record(event: .transferCompleted)
        await persistSnapshot()
    }

    func returnHome() async {
        stopTransferProgressPolling()
        transferStartedAt = nil
        route = .home
        await persistSnapshot()
    }

    private func startTransfer() async {
        transferStartedAt = Date()
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
        await telemetryClient.record(event: .transferStarted)
        await persistSnapshot()
        startTransferProgressPolling()
        transferSnapshot = await transferService.startTransfer(progress: { _ in })
        stopTransferProgressPolling()
        guard route == .transfer else {
            await persistSnapshot()
            return
        }

        await completeTransfer()
    }

    private func startTransferProgressPolling() {
        stopTransferProgressPolling()
        transferProgressPollingTask = Task { [weak self] in
            guard let self else {
                return
            }
            while !Task.isCancelled {
                if let snapshot = await self.transferService.progressSnapshot() {
                    await MainActor.run {
                        self.transferSnapshot = snapshot
                    }
                }
                try? await Task.sleep(for: self.transferProgressPollingInterval)
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
        pairingStatus = snapshot.pairingStatus
        transferSnapshot = snapshot.transferSnapshot
        route = .home
    }

    private func persistSnapshot() async {
        let snapshot = LaunchSnapshot(
            homeSummary: homeSummary,
            permissionSummary: permissionSummary,
            pairingStatus: pairingStatus,
            transferSnapshot: transferSnapshot
        )
        await stateStore.saveLaunchSnapshot(snapshot)
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
