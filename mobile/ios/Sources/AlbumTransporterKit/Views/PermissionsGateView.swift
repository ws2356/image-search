import SwiftUI
#if os(iOS)
import Photos
#endif

struct PermissionsGateView: View {
    @ObservedObject var viewModel: PermissionsPageViewModel

    var body: some View {
        ScrollView {
            PermissionsGateContent()
        }
        .compatibleScrollBounceBasedOnSize()
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
#if os(iOS)
            Button("Update") {
                viewModel.updateMediaAccessTapped()
                PHPhotoLibrary.showLimitedPicker { _ in
                    Task {
                        await viewModel.continueAfterMediaAccessUpdate()
                    }
                }
            }
#endif
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
@available(iOS 17.0, macOS 14.0, *)
#Preview("Limited Library Prompt") {
    PermissionsGateView(
        viewModel: PermissionsPageViewModel(
            model: PermissionsGatePreviewModel(summary: .demo)
        )
    )
}

@available(iOS 17.0, macOS 14.0, *)
#Preview("Low Battery Prompt") {
    PermissionsGateView(
        viewModel: PermissionsPageViewModel(
            model: PermissionsGatePreviewModel(summary: .previewLowBattery)
        )
    )
}

private extension PermissionSummary {
    static let previewLowBattery = PermissionSummary(
        cameraGranted: true,
        notificationsGranted: false,
        mediaScope: .full,
        excludedCategoryDescription: nil,
        lowBatteryWarningNeeded: true,
        isCharging: false
    )
}

@MainActor
private final class PermissionsGatePreviewModel: PermissionsPageModeling {
    var homeSummary = HomeSummary.firstLaunch
    var backupFlowState: MobileBackupFlowState = .pairingCompleted
    var pairingStatus = PairingStatus(
        phase: .paired,
        backupFlowState: .pairingCompleted,
        desktopName: "Desk Mac",
        sessionID: "preview-session",
        transport: .lan,
        message: "Connected."
    )
    var permissionSummary: PermissionSummary
    var removeAfterBackupEnabled = false
    var transferServiceForPageModels: TransferService = PermissionsGatePreviewTransferService()
    var errorSummary = ErrorSummary.generic
    var scannedQRCodeValue = ""
    var permissionService: PermissionService

    init(summary: PermissionSummary) {
        permissionSummary = summary
        permissionService = PermissionsGatePreviewPermissionService(summary: summary)
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

    func beginTelemetrySpan(_ span: MobileTelemetrySpan, attributes: MobileTelemetryAttributes) {
        _ = span
        _ = attributes
    }

    func recordTelemetry(_ event: MobileTelemetryEvent, attributes: MobileTelemetryAttributes) {
        _ = event
        _ = attributes
    }

    func persistSnapshot() {}

    func abortPreflightAndReturnHome(reason: String) async {
        _ = reason
    }

    func recordDialogView(name: String) {
        _ = name
    }
}

private actor PermissionsGatePreviewPermissionService: PermissionService {
    private let summary: PermissionSummary

    init(summary: PermissionSummary) {
        self.summary = summary
    }

    func loadPermissionSummary() async -> PermissionSummary {
        summary
    }
}

private actor PermissionsGatePreviewTransferService: TransferService {
    func startTransfer(progress: @escaping @Sendable (TransferSnapshot) -> Void) async -> TransferSnapshot {
        let snapshot = TransferSnapshot.demo
        progress(snapshot)
        return snapshot
    }

    func stopTransfer(current: TransferSnapshot) async -> InterruptionReason {
        _ = current
        return .stoppedByUser
    }

    func resumeTransfer(
        from snapshot: TransferSnapshot,
        progress: @escaping @Sendable (TransferSnapshot) -> Void
    ) async -> TransferSnapshot {
        progress(snapshot)
        return snapshot
    }

    func completeTransfer(current: TransferSnapshot) async -> TransferSnapshot {
        current
    }

    func progressSnapshot() async -> TransferSnapshot? {
        .demo
    }

    func stageTransferSnapshot(_ snapshot: TransferSnapshot) async {
        _ = snapshot
    }

    func transferCompletionState() async -> TransferCompletionState? {
        nil
    }

    func stageTransferCompletionState(_ completionState: TransferCompletionState?) async {
        _ = completionState
    }

    func moveSuccessfullyTransferredAssetsToRecentlyRemoved() async -> TransferAssetCleanupResult {
        .skipped
    }

    func handleMemoryWarning() async {}
}
#endif
