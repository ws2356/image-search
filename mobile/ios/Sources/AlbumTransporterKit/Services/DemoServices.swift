import Foundation

actor InMemoryBackupSessionStore: BackupSessionStore {
    private var session: BackupSession?

    init(session: BackupSession? = nil) {
        self.session = session
    }

    func loadBackupSession() async -> BackupSession? {
        session
    }

    func saveBackupSession(_ session: BackupSession?) async {
        self.session = session
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
            transport: .lan
        )
    }
}

actor DemoPermissionService: PermissionService {
    var summary: PermissionSummary = .demo
    private var isRemoveAfterBackupEnabled = false

    func loadPermissionSummary() async -> PermissionSummary {
        summary
    }

    func removeAfterBackupEnabled() async -> Bool {
        isRemoveAfterBackupEnabled
    }

    func setRemoveAfterBackupEnabled(_ isEnabled: Bool) async {
        isRemoveAfterBackupEnabled = isEnabled
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
        resumed.phase = .transferring
        progress(resumed)
        return resumed
    }

    func completeTransfer(current: TransferSnapshot) async -> TransferSnapshot {
        try? await Task.sleep(nanoseconds: 150_000_000)

        var completed = current
        completed.transferredCount = current.totalCount
        completed.etaMinutes = nil
        completed.phase = .completed
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
