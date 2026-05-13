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

    private var etaDisplayText: String {
        guard let etaMinutes = snapshot.etaMinutes else {
            return "--"
        }
        return formattedETADisplayText(etaMinutes: etaMinutes)
    }

    private func formattedETADisplayText(etaMinutes: Double) -> String {
        let roundedUpMinutes = max(Int(etaMinutes.rounded(.up)), 1)
        if roundedUpMinutes < 60 {
            return "\(roundedUpMinutes) min"
        }
        let hours = roundedUpMinutes / 60
        let minutes = roundedUpMinutes % 60
        if minutes == 0 {
            return "\(hours) hr"
        }
        return "\(hours) hr \(minutes) min"
    }

    var body: some View {
        VStack(spacing: 20) {
            TransferTransportBadges(transports: snapshot.activeTransportsForDisplay)
            TransferProgressRing(snapshot: snapshot)
            TransferStatsCard(snapshot: snapshot)
            TransferTransferMetaCard(eta: etaDisplayText, skippedCount: snapshot.skippedCount)

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
        max(0, snapshot.totalCount - snapshot.transferredCount - snapshot.failedCount)
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

private struct TransferTransferMetaCard: View {
    let eta: String
    let skippedCount: Int

    var body: some View {
        HStack(spacing: 0) {
            TransferMetaColumn(
                label: "ETA",
                value: eta,
                valueColor: Color(hex: 0x007AFF)
            )
            Divider().frame(height: 40)
            TransferMetaColumn(
                label: "Skipped",
                value: "\(skippedCount)",
                valueColor: Color(hex: 0xFF9F0A)
            )
        }
        .padding(.vertical, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}

private struct TransferMetaColumn: View {
    let label: String
    let value: String
    let valueColor: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: 0x6E6E73))
        }
        .frame(maxWidth: .infinity)
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
    let model = TransferSessionPreviewModel(snapshot: .previewUSB)
    let telemetryService = TransferSessionPreviewTelemetryService()
    TransferSessionView(
        viewModel: TransferPageViewModel(
            model: model,
            telemetryService: telemetryService
        )
    )
}

@available(iOS 17.0, *)
#Preview("Wi-Fi Transfer") {
    let model = TransferSessionPreviewModel(snapshot: .previewWiFi)
    let telemetryService = TransferSessionPreviewTelemetryService()
    TransferSessionView(
        viewModel: TransferPageViewModel(
            model: model,
            telemetryService: telemetryService
        )
    )
}

private extension TransferSnapshot {
    static let previewUSB = TransferSnapshot(
        transferredCount: 248,
        totalCount: 930,
        failedCount: 0,
        skippedCount: 21,
        transport: .usb,
        liveTransports: [.usb, .lan],
        transferSpeedText: "42.80 MB/s",
        etaMinutes: 17,
        statusMessage: "Backing up local photos and videos to the paired desktop.",
        guidanceMessage: "USB is active for the fastest backup. Keep your iPhone unlocked and connected until the transfer finishes.",
        isIncompleteLibrary: false
    )

    static let previewWiFi = TransferSnapshot(
        transferredCount: 112,
        totalCount: 930,
        failedCount: 3,
        skippedCount: 8,
        transport: .lan,
        liveTransports: [.lan],
        transferSpeedText: "4.80 MB/s",
        etaMinutes: 44,
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
    var permissionService: PermissionService = TransferSessionPreviewPermissionService()
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

    func requestStopTransfer() {}

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

private actor TransferSessionPreviewPermissionService: PermissionService {
    private var isRemoveAfterBackupEnabled = false

    func loadPermissionSummary() async -> PermissionSummary {
        .demo
    }

    func removeAfterBackupEnabled() async -> Bool {
        isRemoveAfterBackupEnabled
    }

    func setRemoveAfterBackupEnabled(_ isEnabled: Bool) async {
        isRemoveAfterBackupEnabled = isEnabled
    }
}

@MainActor
private final class TransferSessionPreviewTelemetryService: TelemetryService {
    func recordTelemetry(_ event: MobileTelemetryEvent, attributes: MobileTelemetryAttributes) {}
    func beginTelemetrySpan(_ span: MobileTelemetrySpan, attributes: MobileTelemetryAttributes) {}
    func endTelemetrySpan(
        _ span: MobileTelemetrySpan,
        attributes: MobileTelemetryAttributes,
        status: MobileTelemetrySpanStatus?
    ) {}
    func incrementTelemetryMetric(_ metric: MobileTelemetryMetric, by value: Int, attributes: MobileTelemetryAttributes) {}
    func beginBackupSessionTelemetry() {}
    func recordDialogView(name: String) {}
    func recordInteraction(name: String, location: String) {}
    func forceFlush() {}
}

#endif
