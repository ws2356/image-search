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
        try? await Task.sleep(for: .milliseconds(250))

        return PairingStatus(
            phase: .paired,
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

struct DemoTransferService: TransferService {
    var initialSnapshot: TransferSnapshot = .demo

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        try? await Task.sleep(for: .milliseconds(150))
        progress(initialSnapshot)
        return initialSnapshot
    }

    func stopTransfer(current: TransferSnapshot) async -> InterruptionReason {
        .stoppedByUser
    }

    func resumeTransfer(from snapshot: TransferSnapshot, progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        try? await Task.sleep(for: .milliseconds(150))

        var resumed = snapshot
        resumed.transferredCount = min(snapshot.totalCount, snapshot.transferredCount + 126)
        resumed.failedCount = max(snapshot.failedCount - 1, 0)
        resumed.etaDescription = resumed.transferredCount == resumed.totalCount ? nil : "8 min remaining"
        resumed.statusMessage = "Transfer resumed from the last saved marker."
        resumed.guidanceMessage = "Keep the app in the foreground when possible. iOS may still pause long-running transfers when the app backgrounds."
        progress(resumed)
        return resumed
    }

    func completeTransfer(current: TransferSnapshot) async -> TransferSnapshot {
        try? await Task.sleep(for: .milliseconds(150))

        var completed = current
        completed.transferredCount = current.totalCount
        completed.etaDescription = nil
        completed.statusMessage = "Desktop confirmed that this session is complete."
        completed.guidanceMessage = "You can return to the home screen and start a fresh session whenever new media appears on the device."
        return completed
    }

    func progressSnapshot() async -> TransferSnapshot? {
        initialSnapshot
    }
}
