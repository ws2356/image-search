import SwiftUI
import Combine
import Common

struct HomeView: View {
    @ObservedObject var viewModel: HomePageViewModel

    private let setupSteps = [
        SetupStep(
            id: "open-desktop",
            number: 1,
            title: "Open AuSearch on your PC",
            detail: "Open in your desktop browser. Then install and launch AuSearch.",
            link: "https://aurora.boldman.net"
        ),
        SetupStep(id: "add-mobile-folder", number: 2, title: "Add a Mobile Folder", detail: "Click Add Folder → Mobile Device in the PC app", link: nil),
        SetupStep(id: "scan-qr", number: 3, title: "Scan the QR code", detail: "A QR code appears on screen — scan it below to pair", link: nil),
    ]

    var body: some View {
        ScrollView {
            content
        }
        .compatibleScrollBounceBasedOnSize()
        .appNavigationBar(title: "AuBackup")
    }

    @ViewBuilder
    private var content: some View {
        if hasSessionHistory {
            ReturningHomeContent(summary: summary, onScan: scanQRCode)
        } else {
            FirstTimeHomeContent(
                summary: summary,
                setupSteps: setupSteps,
                onScan: scanQRCode
            )
        }
    }

    private var hasSessionHistory: Bool {
        summary.lastBackupDescription != nil
    }

    private var summary: HomeViewState {
        viewModel.summary
    }

    private func scanQRCode() {
        Task {
            await viewModel.handlePrimaryActionTapped()
        }
    }
}

private struct FirstTimeHomeContent: View {
    let summary: HomeViewState
    let setupSteps: [SetupStep]
    let onScan: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            HomeHeroSection()
            HomeSetupSection(setupSteps: setupSteps)
            HomePrimaryActionButton(action: onScan)

            if summary.permissionScope.isIncomplete {
                HomeWarningBanner(
                    title: "Backup may be incomplete",
                    message: summary.permissionScope.detail
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

private struct ReturningHomeContent: View {
    let summary: HomeViewState
    let onScan: () -> Void

    private var hasStatsCardContent: Bool {
        summary.lastBackupDescription != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(normalizedDesktopDisplayName(summary.desktopName) ?? "")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color(hex: 0x1C1C1E))
                .compatibleTracking(-0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 4)

            VStack(spacing: 12) {
                if let warning = summary.interruptionWarning {
                    HomeInterruptionBanner(message: warning)
                }

                if hasStatsCardContent {
                    HomeStatsCard(summary: summary)
                }

                HomePrimaryActionButton(action: onScan)
                HomeUSBHintBanner()

                if summary.permissionScope.isIncomplete {
                    HomeWarningBanner(
                        title: "Backup may be incomplete",
                        message: summary.permissionScope.detail
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }
}

private struct HomeHeroSection: View {
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        .linearGradient(
                            colors: [Color(hex: 0x0A84FF), Color(hex: 0x0040CC)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: Color(hex: 0x007AFF).opacity(0.45), radius: 12, y: 6)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.white)
            }

            Text("AuBackup")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color(hex: 0x1C1C1E))

            Text("Back up your photos & videos to your PC securely over Wi-Fi or USB or both")
                .font(.subheadline)
                .foregroundStyle(Color(hex: 0x6E6E73))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

private struct HomeSetupSection: View {
    let setupSteps: [SetupStep]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Start on your PC first")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .textCase(.uppercase)
                .compatibleKerning(0.5)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(Array(setupSteps.enumerated()), id: \.element.id) { index, step in
                    HomeSetupStepRow(step: step)
                        .overlay(alignment: .bottomLeading) {
                            if index < setupSteps.count - 1 {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        }
    }
}

private struct HomeSetupStepRow: View {
    let step: SetupStep

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: 0x007AFF))
                    .frame(width: 28, height: 28)
                Text("\(step.number)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                HomeSetupStepDetail(step: step)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}

private struct HomeSetupStepDetail: View {
    let step: SetupStep

    var body: some View {
        Group {
            if let link = step.link {
                (
                    Text("Open ").foregroundColor(Color(hex: 0x6E6E73))
                    + Text(link).foregroundColor(Color(hex: 0x007AFF))
                    + Text(" in your desktop browser. Then install and launch AuSearch.").foregroundColor(Color(hex: 0x6E6E73))
                )
                .textSelection(.enabled)
            } else {
                Text(step.detail)
                    .foregroundStyle(Color(hex: 0x6E6E73))
            }
        }
        .font(.system(size: 13))
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct HomeStatsCard: View {
    let summary: HomeViewState

    var body: some View {
        VStack(spacing: 0) {
            if let lastBackup = summary.lastBackupDescription {
                HomeStatsRow(
                    iconColor: Color(hex: 0x007AFF),
                    iconBackground: Color(hex: 0xE8F4FD),
                    iconName: "clock",
                    title: "Last backup",
                    subtitle: lastBackup
                )
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}

private struct HomeStatsRow: View {
    let iconColor: Color
    let iconBackground: Color
    let iconName: String
    let title: String
    let subtitle: String?
    var titleBold = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 34, height: 34)
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: titleBold ? .semibold : .regular))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: 0x6E6E73))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct HomeInterruptionBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(hex: 0xFF9F0A))
                .font(.system(size: 18))
            VStack(alignment: .leading, spacing: 3) {
                Text("Backup was interrupted")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x555555))
                    .lineSpacing(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xFFF3CD))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct HomeUSBHintBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "cable.connector")
                .foregroundStyle(Color(hex: 0x3B5FC0))
                .font(.system(size: 13))
            Text("USB backups can be up to 5× faster than Wi-Fi. Plug in anytime—AuBackup will switch to USB automatically.")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x3B5FC0))
                .lineSpacing(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xEEF2FF))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct HomeWarningBanner: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 16))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x6E6E73))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xFFF3CD).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct HomePrimaryActionButton: View {
    let action: () -> Void

    var body: some View {
        ActionButton(
            title: "Scan QR Code",
            icon: "qrcode.viewfinder",
            style: .primary,
            height: 56,
            action: action
        )
    }
}

private struct SetupStep: Identifiable {
    let id: String
    let number: Int
    let title: String
    let detail: String
    let link: String?
}

#if DEBUG
@MainActor
final class PreviewBackupSessionProvider: BackupSessionProviding {
    private let currentSubject = CurrentValueSubject<BackupSession?, Never>(nil)
    private let lastSubject: CurrentValueSubject<BackupSession?, Never>

    init(session: BackupSession?) {
        lastSubject = CurrentValueSubject(session)
    }

    var currentBackupSession: BackupSession? { currentSubject.value }

    var currentBackupSessionPublisher: AnyPublisher<BackupSession?, Never> {
        currentSubject.eraseToAnyPublisher()
    }

    var lastBackupSession: BackupSession? { lastSubject.value }

    var lastBackupSessionPublisher: AnyPublisher<BackupSession?, Never> {
        lastSubject.eraseToAnyPublisher()
    }

    func load() async {}

    func saveBackupSession(_ session: BackupSession?) async {
        currentSubject.send(session)
        lastSubject.send(session)
    }
}

@available(iOS 17.0, *)
#Preview("First Launch") {
    let model = HomeViewPreviewPageModel(
        backupSession: nil,
        permissionSummary: .allClear,
        transferSnapshot: nil,
        backupFlowState: .pendingPairing
    )
    let telemetryService = HomeViewPreviewTelemetryService()
    HomeView(
        viewModel: HomePageViewModel(
            model: model,
            telemetryService: telemetryService,
            transportResolver: model.transferService
        )
    )
}

@available(iOS 17.0, *)
#Preview("Returning User") {
    let snapshot = TransferSnapshot(
        transferredCount: 906,
        totalCount: 930,
        failedCount: 3,
        skippedCount: 21,
        transport: .usb,
        liveTransports: [.usb, .lan],
        transferSpeedBytesPerSecond: 42.8 * 1_048_576.0,
        etaMinutes: nil,
        phase: .stopped
    )
    let model = HomeViewPreviewPageModel(
        backupSession: BackupSession(
            sessionID: "preview-session",
            desktopName: "Desk Mac",
            status: .transferStopped,
            updatedAt: Date()
        ),
        permissionSummary: PermissionSummary(
            mediaScope: .limited,
            lowBatteryWarningNeeded: false,
            isCharging: true
        ),
        transferSnapshot: snapshot,
        backupFlowState: .transferStopped
    )
    let telemetryService = HomeViewPreviewTelemetryService()
    HomeView(
        viewModel: HomePageViewModel(
            model: model,
            telemetryService: telemetryService,
            transportResolver: model.transferService
        )
    )
}

@MainActor
private final class HomeViewPreviewPageModel: AppPageModeling {
    let backupSessionProvider: BackupSessionProviding
    var backupFlowState: MobileBackupFlowState = .pendingPairing
    var permissionService: PermissionService
    var transferService: TransferService
    var route: AppRoute = .home

    init(
        backupSession: BackupSession?,
        permissionSummary: PermissionSummary,
        transferSnapshot: TransferSnapshot?,
        backupFlowState: MobileBackupFlowState
    ) {
        backupSessionProvider = PreviewBackupSessionProvider(session: backupSession)
        permissionService = HomeViewPreviewPermissionService(summary: permissionSummary)
        transferService = HomeViewPreviewTransferService(snapshot: transferSnapshot)
        self.backupFlowState = backupFlowState
    }

    func onHomeCompleted(with result: HomePageResult) async {}
    func onScanningCompleted(with result: ScanningPageResult) async {}
    func onPairingCompleted(with result: PairingPageResult) async {}
    func onPermissionsCompleted(with result: PermissionsPageResult) async {}
    func onTransferCompleted(with result: TransferPageResult) async {}
    func onCompletionCompleted(with result: CompletionPageResult) async {}
    func onErrorCompleted(with result: ErrorPageResult) async {}
}

private actor HomeViewPreviewPermissionService: PermissionService {
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

private actor HomeViewPreviewTransferService: TransferService {
    private var snapshot: TransferSnapshot?

    init(snapshot: TransferSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        let currentSnapshot = snapshot ?? .demo
        progress(currentSnapshot)
        snapshot = currentSnapshot
        return currentSnapshot
    }

    func stopTransfer() async -> InterruptionReason {
        return .stoppedByUser
    }

    func completeTransfer() async -> TransferSnapshot {
        let completedSnapshot = snapshot ?? .demo
        snapshot = completedSnapshot
        return completedSnapshot
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

@MainActor
private final class HomeViewPreviewTelemetryService: TelemetryService {
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
