import SwiftUI

struct TransferSessionView: View {
    @ObservedObject var viewModel: TransferPageViewModel

    private var snapshot: TransferSnapshot {
        viewModel.snapshot
    }

    var body: some View {
        ScrollView {
            TransferSessionContent(snapshot: snapshot, onStop: viewModel.requestStopTransfer)
        }
        .compatibleScrollBounceBasedOnSize()
        .task {
            await viewModel.orchestrateTransfer()
        }
        .compatibleOnChange(of: viewModel.isShowingStopConfirmation) { isPresented in
            guard isPresented else { return }
            viewModel.recordStopConfirmationPresented()
        }
        .alert("Stop backup?", isPresented: viewModel.isShowingStopConfirmationBinding) {
            Button("Stop Sending More Items", role: .destructive) {
                Task {
                    await viewModel.confirmStopTransfer()
                }
            }
            Button("Keep Backing Up", role: .cancel) {
                viewModel.keepBackingUp()
            }
        } message: {
            Text("The desktop may continue indexing items that already transferred before the stop request.")
        }
    }
}

private struct TransferSessionContent: View {
    let snapshot: TransferSnapshot
    let onStop: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            TransferTransportBadges(transports: snapshot.activeTransportsForDisplay)
            TransferProgressRing(snapshot: snapshot)
            TransferStatsCard(snapshot: snapshot)

            if let eta = snapshot.etaDescription {
                TransferEstimatedTimeCard(eta: eta)
            }

            TransferGuidanceBanner(snapshot: snapshot)

            if snapshot.isIncompleteLibrary {
                TransferIncompleteLibraryBanner()
            }

            TransferStopButton(action: onStop)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

private struct TransferTransportBadges: View {
    let transports: [TransferTransport]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(transports, id: \.rawValue) { transport in
                TransferTransportBadge(transport: transport)
            }
        }
    }
}

private struct TransferTransportBadge: View {
    let transport: TransferTransport

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: transport.systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(transport.title)
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(transport.foregroundColor)
        .background(transport.backgroundColor)
        .clipShape(Capsule())
    }
}

private struct TransferProgressRing: View {
    let snapshot: TransferSnapshot

    private var progressPercent: Int {
        Int(snapshot.progress * 100)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: 0xE5E5EA), lineWidth: 12)

            Circle()
                .trim(from: 0, to: snapshot.progress)
                .stroke(
                    snapshot.transport.accentColor,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 6) {
                Text("\(progressPercent)%")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                Text(snapshot.transferSpeedText ?? "0.00 MB/s")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x6E6E73))
            }
        }
        .frame(width: 180, height: 180)
        .padding(.vertical, 8)
    }
}

private struct TransferStatsCard: View {
    let snapshot: TransferSnapshot

    private var remainingCount: Int {
        max(0, snapshot.totalCount - snapshot.transferredCount)
    }

    var body: some View {
        HStack(spacing: 0) {
            TransferStatColumn(
                label: "Sent",
                value: "\(snapshot.transferredCount)",
                color: Color(hex: 0x30D158)
            )
            Divider().frame(height: 40)
            TransferStatColumn(
                label: "Remaining",
                value: "\(remainingCount)",
                color: Color(hex: 0x007AFF)
            )
            Divider().frame(height: 40)
            TransferStatColumn(
                label: "Failed",
                value: "\(snapshot.failedCount)",
                color: Color(hex: 0xFF453A)
            )
        }
        .padding(.vertical, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}

private struct TransferStatColumn: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: 0x6E6E73))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct TransferEstimatedTimeCard: View {
    let eta: String

    var body: some View {
        VStack(spacing: 4) {
            Text("Estimated time")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x6E6E73))
            Text(eta)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color(hex: 0x1C1C1E))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}

private struct TransferGuidanceBanner: View {
    let snapshot: TransferSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: snapshot.transport.guidanceSystemImage)
                .foregroundStyle(snapshot.transport.guidanceAccentColor)
            Text(snapshot.guidanceMessage)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(snapshot.transport.guidanceBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct TransferIncompleteLibraryBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Only the subset currently granted by iOS is being transferred.")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x6E6E73))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xFFF3CD).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct TransferStopButton: View {
    let action: () -> Void

    var body: some View {
        ActionButton(
            title: "Stop Backup",
            icon: "stop.fill",
            style: .destructive,
            action: action
        )
    }
}

private extension TransferTransport {
    var accentColor: Color {
        switch self {
        case .lan:
            return Color(hex: 0x007AFF)
        case .usb:
            return Color(hex: 0x30D158)
        }
    }

    var backgroundColor: Color {
        switch self {
        case .lan:
            return Color(hex: 0xE8F4FD)
        case .usb:
            return Color(hex: 0xE6F9ED)
        }
    }

    var foregroundColor: Color {
        accentColor
    }

    var guidanceBackgroundColor: Color {
        switch self {
        case .lan:
            return Color(hex: 0xEEF2FF)
        case .usb:
            return Color(hex: 0xE6F9ED)
        }
    }

    var guidanceAccentColor: Color {
        switch self {
        case .lan:
            return Color(hex: 0x3B5FC0)
        case .usb:
            return Color(hex: 0x30D158)
        }
    }

    var guidanceSystemImage: String {
        switch self {
        case .lan:
            return "bolt.horizontal.fill"
        case .usb:
            return "checkmark.circle.fill"
        }
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("USB Transfer") {
    TransferSessionView(
        viewModel: TransferPageViewModel(
            model: TransferSessionPreviewModel(snapshot: .previewUSB)
        )
    )
}

@available(iOS 17.0, *)
#Preview("Wi-Fi Transfer") {
    TransferSessionView(
        viewModel: TransferPageViewModel(
            model: TransferSessionPreviewModel(snapshot: .previewWiFi)
        )
    )
}

private extension TransferSnapshot {
    static let previewUSB = TransferSnapshot(
        transferredCount: 248,
        totalCount: 930,
        failedCount: 0,
        transport: .usb,
        liveTransports: [.usb, .lan],
        transferSpeedText: "42.80 MB/s",
        etaDescription: "17 min remaining",
        statusMessage: "Backing up local photos and videos to the paired desktop.",
        guidanceMessage: "USB is active for the fastest backup. Keep your iPhone unlocked and connected until the transfer finishes.",
        isIncompleteLibrary: false
    )

    static let previewWiFi = TransferSnapshot(
        transferredCount: 112,
        totalCount: 930,
        failedCount: 3,
        transport: .lan,
        liveTransports: [.lan],
        transferSpeedText: "4.80 MB/s",
        etaDescription: "44 min remaining",
        statusMessage: "Backing up local photos and videos to the paired desktop.",
        guidanceMessage: "USB backups are generally faster and more stable than Wi-Fi. Plug in anytime to let the session upgrade automatically when available.",
        isIncompleteLibrary: true
    )
}

@MainActor
private final class TransferSessionPreviewModel: TransferPageModeling {
    var homeSummary = HomeSummary.firstLaunch
    var backupFlowState: MobileBackupFlowState = .transferInProgress
    var pairingStatus = PairingStatus(
        phase: .paired,
        backupFlowState: .transferInProgress,
        desktopName: "Desk Mac",
        sessionID: "preview-session",
        transport: .usb,
        message: "Connected."
    )
    var permissionSummary = PermissionSummary.demo
    var removeAfterBackupEnabled = false
    var route: AppRoute = .transfer
    var errorSummary = ErrorSummary.generic
    var scannedQRCodeValue = ""
    var transferServiceForPageModels: TransferService { transferService }
    var transferServiceForTransferView: TransferService { transferService }

    private let transferService: TransferSessionPreviewTransferService

    init(snapshot: TransferSnapshot) {
        transferService = TransferSessionPreviewTransferService(snapshot: snapshot)
        pairingStatus.transport = snapshot.transport
    }

    func handleResultForPage(_ page: AppRoute, result: PageResult, target: PageTarget?) async {
        _ = page
        _ = result
        _ = target
    }

    func setRemoveAfterBackupEnabled(_ isEnabled: Bool) {
        removeAfterBackupEnabled = isEnabled
    }

    func requestStopTransfer() {}

    func recordInteraction(name: String, location: String) {
        _ = name
        _ = location
    }

    func recordDialogView(name: String) {
        _ = name
    }

    func persistSnapshot() {}
}

private actor TransferSessionPreviewTransferService: TransferService {
    private var snapshot: TransferSnapshot

    init(snapshot: TransferSnapshot) {
        self.snapshot = snapshot
    }

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        progress(snapshot)
        return snapshot
    }

    func stopTransfer(current: TransferSnapshot) async -> InterruptionReason {
        snapshot = current
        return .stoppedByUser
    }

    func resumeTransfer(
        from snapshot: TransferSnapshot,
        progress: @escaping @Sendable (TransferSnapshot) -> Void
    ) async -> TransferSnapshot {
        self.snapshot = snapshot
        progress(snapshot)
        return snapshot
    }

    func completeTransfer(current: TransferSnapshot) async -> TransferSnapshot {
        snapshot = current
        return current
    }

    func progressSnapshot() async -> TransferSnapshot? {
        snapshot
    }

    func stageTransferSnapshot(_ snapshot: TransferSnapshot) async {
        self.snapshot = snapshot
    }

    func transferCompletionState() async -> TransferCompletionState? {
        nil
    }

    func stageTransferCompletionState(_ completionState: TransferCompletionState?) async {
        if let completionState {
            snapshot = completionState.snapshot
        }
    }

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        .skipped
    }

    func handleMemoryWarning() async {}
}
#endif
