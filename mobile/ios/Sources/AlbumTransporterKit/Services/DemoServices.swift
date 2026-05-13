import Foundation

actor InMemoryAppStateStore: AppStateStore {
    private var snapshot: LaunchSnapshot

    init(snapshot: LaunchSnapshot = .firstLaunch) {
        self.snapshot = snapshot
    }

    func loadLaunchSnapshot() async -> LaunchSnapshot {
        snapshot
    }

    func saveLaunchSnapshot(_ snapshot: LaunchSnapshot) async {
        self.snapshot = snapshot
    }
}

struct DemoPairingService: PairingService {
    var desktopName = "Studio Mac"

    func startPairing(using payload: PairingQRCodePayload) async -> PairingStatus {
        try? await Task.sleep(nanoseconds: 250_000_000)

        return PairingStatus(
            phase: .paired,
            backupFlowState: .pairingCompleted,
            desktopName: desktopName,
            sessionID: payload.sessionID,
            transport: .lan,
            message: "Secure local pairing established using payload \(payload.sessionID). The desktop will validate whether this is a new, repeat, or resumable session."
        )
    }
}

struct DemoPermissionService: PermissionService {
    var summary: PermissionSummary = .demo

    func loadPermissionSummary() async -> PermissionSummary {
        summary
    }
}

actor DemoTransferService: TransferService {
    private var currentSnapshot: TransferSnapshot
    private var completionState: TransferCompletionState?

    init(initialSnapshot: TransferSnapshot = .demo) {
        self.currentSnapshot = initialSnapshot
    }

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        try? await Task.sleep(nanoseconds: 150_000_000)
        progress(currentSnapshot)
        completionState = nil
        return currentSnapshot
    }

    func stopTransfer(current: TransferSnapshot) async -> InterruptionReason {
        .stoppedByUser
    }

    func resumeTransfer(from snapshot: TransferSnapshot, progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        try? await Task.sleep(nanoseconds: 150_000_000)

        var resumed = snapshot
        resumed.transferredCount = min(snapshot.totalCount, snapshot.transferredCount + 126)
        resumed.failedCount = max(snapshot.failedCount - 1, 0)
        resumed.etaMinutes = resumed.transferredCount == resumed.totalCount ? nil : 8
        resumed.statusMessage = "Transfer resumed from the last saved marker."
        resumed.guidanceMessage = "Keep the app in the foreground when possible. iOS may still pause long-running transfers when the app backgrounds."
        progress(resumed)
        return resumed
    }

    func completeTransfer(current: TransferSnapshot) async -> TransferSnapshot {
        try? await Task.sleep(nanoseconds: 150_000_000)

        var completed = current
        completed.transferredCount = current.totalCount
        completed.etaMinutes = nil
        completed.statusMessage = "Desktop confirmed that this session is complete."
        completed.guidanceMessage = "You can return to the home screen and start a fresh session whenever new media appears on the device."
        currentSnapshot = completed
        return completed
    }

    func progressSnapshot() async -> TransferSnapshot? {
        currentSnapshot
    }

    func stageTransferSnapshot(_ snapshot: TransferSnapshot) async {
        currentSnapshot = snapshot
    }

    func transferCompletionState() async -> TransferCompletionState? {
        completionState
    }

    func stageTransferCompletionState(_ completionState: TransferCompletionState?) async {
        self.completionState = completionState
        if let snapshot = completionState?.snapshot {
            currentSnapshot = snapshot
        }
    }

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        .skipped
    }
}
