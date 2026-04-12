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
    private(set) var interruptionReason = InterruptionReason.desktopUnreachable
    private(set) var completionSummary = CompletionSummary.demo
    var scannedQRCodeValue = ""

    var isShowingStopConfirmation = false
    var isShowingLowBatteryWarning = false

    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var transferProgressPollingTask: Task<Void, Never>?
    @ObservationIgnored private let transferProgressPollingInterval: Duration
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
        case .interrupted:
            return "Backup Interrupted"
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
        await telemetryClient.record(event: .appLaunched)
    }

    func handleHomePrimaryAction() async {
        switch homeSummary.primaryAction {
        case .scanDesktopQRCode:
            await openScanFlow()
        case .resumeBackup:
            route = .interrupted
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
        if permissionSummary.lowBatteryWarningNeeded && !permissionSummary.isCharging {
            isShowingLowBatteryWarning = true
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
        interruptionReason = await transferService.stopTransfer(current: transferSnapshot)
        homeSummary = .resumable(
            desktopName: homeSummary.desktopName,
            remainingItems: max(transferSnapshot.totalCount - transferSnapshot.transferredCount, 0),
            permissionScope: permissionSummary.mediaScope
        )
        route = .interrupted

        await telemetryClient.record(event: .transferStopped)
        await persistSnapshot()
    }

    func resumeTransfer() async {
        route = .transfer
        transferSnapshot.statusMessage = "Resuming the backup with the paired desktop."
        startTransferProgressPolling()
        transferSnapshot = await transferService.resumeTransfer(
            from: transferSnapshot,
            progress: { _ in }
        )
        stopTransferProgressPolling()

        await telemetryClient.record(event: .resumeTapped)
        await persistSnapshot()
    }

    func completeTransfer() async {
        stopTransferProgressPolling()
        transferSnapshot = await transferService.completeTransfer(current: transferSnapshot)
        completionSummary = CompletionSummary(
            title: "Backup Complete!",
            message: "Desktop confirmed \(transferSnapshot.totalCount) eligible items for this session. Media that already transferred may still be indexing on desktop."
        )
        homeSummary = .completed(
            desktopName: homeSummary.desktopName,
            permissionScope: permissionSummary.mediaScope,
            lastBackupDescription: "Last backup completed just now."
        )
        route = .completed

        await telemetryClient.record(event: .transferCompleted)
        await persistSnapshot()
    }

    func returnHome() async {
        stopTransferProgressPolling()
        route = .home
        await persistSnapshot()
    }

    private func startTransfer() async {
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
        await persistSnapshot()
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
        interruptionReason = snapshot.lastInterruptionReason ?? .desktopUnreachable
        route = .home
    }

    private func persistSnapshot() async {
        let snapshot = LaunchSnapshot(
            homeSummary: homeSummary,
            permissionSummary: permissionSummary,
            pairingStatus: pairingStatus,
            transferSnapshot: transferSnapshot,
            lastInterruptionReason: homeSummary.primaryAction.isResumeAction ? interruptionReason : nil
        )
        await stateStore.saveLaunchSnapshot(snapshot)
    }
}
