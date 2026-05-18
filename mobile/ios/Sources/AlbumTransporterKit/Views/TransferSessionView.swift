import SwiftUI

struct TransferSessionView: View {
    @ObservedObject var viewModel: TransferPageViewModel

    private var snapshot: TransferSnapshot {
        viewModel.snapshot
    }

    var body: some View {
        ScrollView {
            TransferSessionContent(
                snapshot: snapshot,
                isIncompleteLibrary: viewModel.isIncompleteLibrary,
                onStop: viewModel.requestStopTransfer
            )
        }
        .compatibleScrollBounceBasedOnSize()
        .task {
            await viewModel.orchestrateTransfer()
        }
        .onAppear {
            Task {
                await viewModel.loadFromViewLifecycle()
            }
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
    let isIncompleteLibrary: Bool
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

            if isIncompleteLibrary {
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
                Text(formattedTransferSpeedText(snapshot.transferSpeedBytesPerSecond))
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x6E6E73))
            }
        }
        .frame(width: 180, height: 180)
        .padding(.vertical, 8)
    }
}

private func formattedTransferSpeedText(_ bytesPerSecond: Double?) -> String {
    String(format: "%.2f MB/s", (bytesPerSecond ?? 0) / 1_048_576.0)
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

    private var message: String {
        if let failureMessage = snapshot.failureMessage, snapshot.phase == .failed {
            return failureMessage
        }
        switch snapshot.phase {
        case .preparing:
            return "Keep the app in the foreground while the phone prepares the backup session."
        case .transferring:
            if snapshot.failedCount > 0 {
                return "Some items have failed so far. Let the current run finish, then inspect the MobileTransfer device logs for per-item errors."
            }
            switch snapshot.transport {
            case .usb:
                return "USB is active for the fastest backup. Keep your iPhone unlocked and connected until the transfer finishes."
            case .lan:
                return "Keep the app in the foreground while the phone sends items to the desktop. Plug in USB anytime to let the session upgrade automatically when available."
            }
        case .stopped:
            return "Start a new backup session to continue sending any remaining accessible items."
        case .completed:
            return "You can return home and start another backup whenever new media appears on the device."
        case .failed:
            return "Retry the backup after confirming the paired desktop is reachable and ready."
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: snapshot.transport.guidanceSystemImage)
                .foregroundStyle(snapshot.transport.guidanceAccentColor)
            Text(message)
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
    let model = TransferSessionPreviewModel(
        snapshot: .previewUSB,
        permissionSummary: .allClear
    )
    let telemetryService = TransferSessionPreviewTelemetryService()
    TransferSessionView(
        viewModel: TransferPageViewModel(
            model: model,
            telemetryService: telemetryService,
            transportResolver: model.transferService
        )
    )
}

@available(iOS 17.0, *)
#Preview("Wi-Fi Transfer") {
    let model = TransferSessionPreviewModel(
        snapshot: .previewWiFi,
        permissionSummary: PermissionSummary(
            mediaScope: .limited,
            lowBatteryWarningNeeded: false,
            isCharging: true
        )
    )
    let telemetryService = TransferSessionPreviewTelemetryService()
    TransferSessionView(
        viewModel: TransferPageViewModel(
            model: model,
            telemetryService: telemetryService,
            transportResolver: model.transferService
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
        transferSpeedBytesPerSecond: 42.8 * 1_048_576.0,
        etaMinutes: 17,
        phase: .transferring
    )

    static let previewWiFi = TransferSnapshot(
        transferredCount: 112,
        totalCount: 930,
        failedCount: 3,
        skippedCount: 8,
        transport: .lan,
        liveTransports: [.lan],
        transferSpeedBytesPerSecond: 4.8 * 1_048_576.0,
        etaMinutes: 44,
        phase: .transferring
    )
}

@MainActor
private final class TransferSessionPreviewModel: TransferPageModeling {
    let backupSessionProvider: BackupSessionProviding
    var backupFlowState: MobileBackupFlowState = .transferInProgress
    var permissionService: PermissionService
    var route: AppRoute = .transfer

    let transferService: TransferService

    init(snapshot: TransferSnapshot, permissionSummary: PermissionSummary) {
        backupSessionProvider = PreviewBackupSessionProvider(
            session: BackupSession(
                sessionID: "preview-session",
                desktopName: "Desk Mac",
                status: .paired,
                updatedAt: Date()
            )
        )
        permissionService = TransferSessionPreviewPermissionService(summary: permissionSummary)
        transferService = TransferSessionPreviewTransferService(snapshot: snapshot)
    }

    func onHomeCompleted(with result: HomePageResult) async {}
    func onScanningCompleted(with result: ScanningPageResult) async {}
    func onPairingCompleted(with result: PairingPageResult) async {}
    func onPermissionsCompleted(with result: PermissionsPageResult) async {}
    func onTransferCompleted(with result: TransferPageResult) async {}
    func onCompletionCompleted(with result: CompletionPageResult) async {}
    func onErrorCompleted(with result: ErrorPageResult) async {}
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

    func stopTransfer() async -> InterruptionReason {
        return .stoppedByUser
    }

    func completeTransfer() async -> TransferSnapshot {
        snapshot.phase = .completed
        return snapshot
    }

    func progressSnapshot() async -> TransferSnapshot? {
        snapshot
    }

    func transferCompletionState() async -> TransferCompletionState? {
        nil
    }

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        .skipped
    }

    func handleMemoryWarning() async {}
}

private actor TransferSessionPreviewPermissionService: PermissionService {
    private let summary: PermissionSummary
    private var isRemoveAfterBackupEnabled = false

    init(summary: PermissionSummary) {
        self.summary = summary
    }

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
