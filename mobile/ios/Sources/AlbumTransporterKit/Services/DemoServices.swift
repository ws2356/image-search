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

    func startPairing(using payload: PairingQRCodePayload) async -> Result<PairingResponse, PairingError> {
        try? await Task.sleep(nanoseconds: 250_000_000)

        return .success(
            PairingResponse(
                sessionID: payload.sessionID,
                desktopName: desktopName,
                transport: .lan
            )
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

    func stopTransfer() async -> InterruptionReason {
        .stoppedByUser
    }

    func completeTransfer() async -> TransferSnapshot {
        try? await Task.sleep(nanoseconds: 150_000_000)

        var completed = currentSnapshot
        completed.transferredCount = completed.totalCount
        completed.etaMinutes = nil
        completed.phase = .completed
        currentSnapshot = completed
        completionState = TransferCompletionState(
            snapshot: completed,
            cleanupResult: .skipped,
            completedAt: Date(),
            sessionDuration: nil
        )
        return completed
    }

    func progressSnapshot() async -> TransferSnapshot? {
        currentSnapshot
    }

    func isUSBTransportAlive() async -> Bool {
        currentSnapshot.liveTransports?.contains(.usb) ?? (currentSnapshot.transport == .usb)
    }

    func transferCompletionState() async -> TransferCompletionState? {
        completionState
    }

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        .skipped
    }
}
