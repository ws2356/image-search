import SwiftUI
import Photos
import Common

struct PermissionsGateView: View {
    @ObservedObject var viewModel: PermissionsPageViewModel

    var body: some View {
        ScrollView {
            PermissionsGateContent()
        }
        .compatibleScrollBounceBasedOnSize()
        .appNavigationBar(title: "Permissions")
        .task {
            await viewModel.startPreflight()
        }
        .compatibleOnChange(of: viewModel.isShowingLowBatteryWarning) { isPresented in
            guard isPresented else { return }
            viewModel.recordLowBatteryDialogPresented()
        }
        .compatibleOnChange(of: viewModel.isShowingMediaAccessAlert) { isPresented in
            guard isPresented else { return }
            viewModel.recordMediaAccessDialogPresented()
        }
        .compatibleOnChange(of: viewModel.isShowingRemoveAfterBackupPrompt) { isPresented in
            guard isPresented else { return }
            viewModel.recordRemoveAfterBackupDialogPresented()
        }
        .alert("Low battery detected", isPresented: $viewModel.isShowingLowBatteryWarning) {
            Button("Continue Anyway") {
                Task {
                    await viewModel.continuePastLowBattery()
                }
            }
            Button("Not Now", role: .cancel) {
                Task {
                    await viewModel.cancelFromLowBattery()
                }
            }
        } message: {
            Text("Long transfers are more likely to pause when battery is low. Connect the device to a charger or desktop if you can.")
        }
        .alert("Full media access recommended", isPresented: $viewModel.isShowingMediaAccessAlert) {
            Button("Update") {
                viewModel.updateMediaAccessTapped()
                if viewModel.summary.mediaScope == .limited {
                    PHPhotoLibrary.showLimitedPicker { _ in
                        Task {
                            await viewModel.continueAfterMediaAccessUpdate()
                        }
                    }
                } else {
                    Task {
                        await viewModel.requestMediaAccessAndContinue()
                    }
                }
            }
            Button("Not now", role: .cancel) {
                Task {
                    await viewModel.continueBackupFromMediaAccessNotNow()
                }
            }
        } message: {
            Text(viewModel.mediaAccessAlertMessage)
        }
        .alert("After backup, remove transferred media?", isPresented: $viewModel.isShowingRemoveAfterBackupPrompt) {
            Button("Remove", role: .destructive) {
                Task {
                    await viewModel.selectRemoveAfterBackupPreference(true)
                }
            }
            Button("Do not remove", role: .cancel) {
                Task {
                    await viewModel.selectRemoveAfterBackupPreference(false)
                }
            }
        } message: {
            Text("Choose whether successfully transferred photos and videos should be moved to Recently Removed on this device after backup completes.")
        }
    }
}

private struct PermissionsGateContent: View {
    var body: some View {
        VStack(spacing: 20) {
            PermissionsPreflightHero()
            PermissionsPreflightCard()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

private struct PermissionsPreflightHero: View {
    var body: some View {
        VStack(spacing: 12) {
            heroCircle(icon: "lock.shield.fill", gradient: [Color(hex: 0x007AFF), Color(hex: 0x0055D4)])

            Text("Backup preflight")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color(hex: 0x1C1C1E))

            Text("Preparing backup...")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: 0x6E6E73))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct PermissionsPreflightCard: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
                .tint(Color(hex: 0x007AFF))
                .padding(.top, 6)

            Text("Checking media access, battery status, and backup cleanup preference. Continue in each prompt to begin transfer automatically.")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}

#if DEBUG
@available(iOS 17.0, *)
#Preview("Limited Library Prompt") {
    let model = PermissionsGatePreviewModel(summary: .demo)
    let telemetryService = PermissionsGatePreviewTelemetryService()
    PermissionsGateView(
        viewModel: PermissionsPageViewModel(
            model: model,
            telemetryService: telemetryService
        )
    )
}

@available(iOS 17.0, *)
#Preview("Low Battery Prompt") {
    let model = PermissionsGatePreviewModel(summary: .previewLowBattery)
    let telemetryService = PermissionsGatePreviewTelemetryService()
    PermissionsGateView(
        viewModel: PermissionsPageViewModel(
            model: model,
            telemetryService: telemetryService
        )
    )
}

private extension PermissionSummary {
    static let previewLowBattery = PermissionSummary(
        mediaScope: .full,
        lowBatteryWarningNeeded: true,
        isCharging: false
    )
}

@MainActor
private final class PermissionsGatePreviewModel: PermissionsPageModeling {
    let backupSessionProvider: BackupSessionProviding = PreviewBackupSessionProvider(
        session: BackupSession(
            sessionID: "preview-session",
            desktopName: "Desk Mac",
            status: .pairingCompleted,
            updatedAt: Date()
        )
    )
    var backupFlowState: MobileBackupFlowState = .pairingCompleted
    var pairingService: PairingService = DemoPairingService()
    var transferService: TransferService = PermissionsGatePreviewTransferService()
    var route: AppRoute = .permissions
    var permissionService: PermissionService

    init(summary: PermissionSummary) {
        permissionService = PermissionsGatePreviewPermissionService(summary: summary)
    }

    func onHomeCompleted(with result: HomePageResult) async {}
    func onScanningCompleted(with result: ScanningPageResult) async {}
    func onPairingCompleted(with result: PairingPageResult) async {}
    func onPermissionsCompleted(with result: PermissionsPageResult) async {}
    func onTransferCompleted(with result: TransferPageResult) async {}
    func onCompletionCompleted(with result: CompletionPageResult) async {}
    func onErrorCompleted(with result: ErrorPageResult) async {}
}

private actor PermissionsGatePreviewPermissionService: PermissionService {
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

private actor PermissionsGatePreviewTransferService: TransferService {
    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        let snapshot = TransferSnapshot.demo
        progress(snapshot)
        return snapshot
    }

    func stopTransfer() async -> InterruptionReason {
        return .stoppedByUser
    }

    func completeTransfer() async -> TransferSnapshot {
        .demo
    }

    func progressSnapshot() async -> TransferSnapshot? {
        .demo
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
private final class PermissionsGatePreviewTelemetryService: TelemetryService {
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
