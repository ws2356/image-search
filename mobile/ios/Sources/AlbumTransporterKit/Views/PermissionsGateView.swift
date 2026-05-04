import SwiftUI
#if os(iOS)
import Photos
#endif

struct PermissionsGateView: View {
    let viewModel: PermissionsPageViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .compatibleScrollBounceBasedOnSize()
        .task {
            await viewModel.startPreflight()
        }
        .onChange(of: viewModel.isShowingLowBatteryWarning) { isPresented in
            guard isPresented else { return }
            viewModel.recordLowBatteryDialogPresented()
        }
        .onChange(of: viewModel.isShowingMediaAccessAlert) { isPresented in
            guard isPresented else { return }
            viewModel.recordMediaAccessDialogPresented()
        }
        .onChange(of: viewModel.isShowingRemoveAfterBackupPrompt) { isPresented in
            guard isPresented else { return }
            viewModel.recordRemoveAfterBackupDialogPresented()
        }
        .alert("Low battery detected", isPresented: viewModel.isShowingLowBatteryWarningBinding) {
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
        .alert("Full media access recommended", isPresented: viewModel.isShowingMediaAccessAlertBinding) {
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
        .alert("After backup, remove transferred media?", isPresented: viewModel.isShowingRemoveAfterBackupPromptBinding) {
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
