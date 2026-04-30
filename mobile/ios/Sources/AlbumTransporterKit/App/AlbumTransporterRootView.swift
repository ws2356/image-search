import SwiftUI
import Foundation
import Factory
#if os(iOS)
import UIKit
#endif
import Photos

@MainActor
public struct AlbumTransporterRootView: View {
    @StateObject private var model: MobileAppModel

    public init() {
        self.init(container: .shared)
    }

    init(container: Container) {
        _model = StateObject(wrappedValue: container.mobileAppModel())
    }

    public var body: some View {
        navigationContainer
            .background(backgroundGradient)
            .task {
                await model.load()
            }
            .task(id: model.route) {
                model.recordPageView(name: model.route.rawValue)
            }
            .onChange(of: model.isShowingStopConfirmation) { isPresented in
                guard isPresented else { return }
                model.recordDialogView(name: "stop_confirmation")
            }
            .onChange(of: model.isShowingLowBatteryWarning) { isPresented in
                guard isPresented else { return }
                model.recordDialogView(name: "low_battery_warning")
            }
            .onChange(of: model.isShowingMediaAccessAlert) { isPresented in
                guard isPresented else { return }
                model.recordDialogView(name: "media_access_alert")
            }
            .onChange(of: model.isShowingRemoveAfterBackupPrompt) { isPresented in
                guard isPresented else { return }
                model.recordDialogView(name: "remove_after_backup_prompt")
            }
            .confirmationDialog(
                "Stop backup?",
                isPresented: $model.isShowingStopConfirmation,
                titleVisibility: .visible
            ) {
                Button("Stop Sending More Items", role: .destructive) {
                    model.recordInteraction(name: "stop_confirmed", location: "stop_confirmation")
                    Task {
                        await model.confirmStopTransfer()
                    }
                }
                Button("Keep Backing Up", role: .cancel) {
                    model.recordInteraction(name: "stop_cancelled", location: "stop_confirmation")
                }
            } message: {
                Text("The desktop may continue indexing items that already transferred before the stop request.")
            }
            .alert("Low battery detected", isPresented: $model.isShowingLowBatteryWarning) {
                Button("Continue Anyway") {
                    model.recordInteraction(name: "continue_anyway_tapped", location: "low_battery_warning")
                    Task {
                        await model.continuePastLowBatteryWarning()
                    }
                }
                Button("Not Now", role: .cancel) {
                    model.recordInteraction(name: "not_now_tapped", location: "low_battery_warning")
                    Task {
                        await model.cancelBackupFromLowBatteryWarning()
                    }
                }
            } message: {
                Text("Long transfers are more likely to pause when battery is low. Connect the device to a charger or desktop if you can.")
            }
            .alert("Full media access recommended", isPresented: $model.isShowingMediaAccessAlert) {
#if os(iOS)
                Button("Update") {
                    model.recordInteraction(name: "update_media_access_tapped", location: "media_access_alert")
                    Task {
                        PHPhotoLibrary.showLimitedPicker { _ in
                            Task {
                                await model.continueBackupFromMediaAccess()
                            }
                        }
                    }
                }
#endif
                Button("Not now", role: .cancel) {
                    model.recordInteraction(name: "not_now_tapped", location: "media_access_alert")
                    Task {
                        await model.continueBackupFromMediaAccess()
                    }
                }
            } message: {
                Text(model.mediaAccessAlertMessage)
            }
            .alert("After backup, remove transferred media?", isPresented: $model.isShowingRemoveAfterBackupPrompt) {
                Button("Remove", role: .destructive) {
                    model.recordInteraction(name: "remove_after_backup_selected", location: "remove_after_backup_prompt")
                    Task {
                        await model.selectRemoveAfterBackupPreferenceAndContinue(true)
                    }
                }
                Button("Do not remove", role: .cancel) {
                    model.recordInteraction(name: "keep_originals_selected", location: "remove_after_backup_prompt")
                    Task {
                        await model.selectRemoveAfterBackupPreferenceAndContinue(false)
                    }
                }
            } message: {
                Text("Choose whether successfully transferred photos and videos should be moved to Recently Removed on this device after backup completes.")
            }
            .confirmationDialog(
                "Start a new backup session?",
                isPresented: $model.isShowingIncomingLinkReplacementConfirmation,
                titleVisibility: .visible
            ) {
                Button("Start New Session", role: .destructive) {
                    model.recordInteraction(name: "incoming_link_replace_confirmed", location: "incoming_link_confirmation")
                    Task {
                        await model.confirmIncomingUniversalLinkReplacement()
                    }
                }
                Button("Keep Current Backup", role: .cancel) {
                    model.recordInteraction(name: "incoming_link_replace_cancelled", location: "incoming_link_confirmation")
                    model.cancelIncomingUniversalLinkReplacement()
                }
            } message: {
                Text("A new desktop pairing link was opened. Starting it now will stop the current transfer.")
            }
            .onOpenURL { url in
                Task {
                    await model.handleIncomingUniversalLink(url)
                }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { userActivity in
                guard let url = userActivity.webpageURL else {
                    return
                }
                Task {
                    await model.handleIncomingUniversalLink(url)
                }
            }
    }

    @ViewBuilder
    private var navigationContainer: some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                currentScreen
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .navigationTitle(model.navigationTitle)
#if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarBackground(navigationBarBackground, for: .navigationBar)
                    .toolbarColorScheme(.light, for: .navigationBar)
#endif
            }
        } else {
            NavigationView {
                currentScreen
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .navigationTitle(model.navigationTitle)
#if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
#endif
            }
#if os(iOS)
            .navigationViewStyle(.stack)
#endif
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch model.route {
        case .home:
            let homeViewModel = HomePageViewModel(model: model)
            HomeView(
                summary: homeViewModel.summary,
                onPrimaryAction: {
                    model.recordInteraction(name: "primary_action_tapped", location: "home")
                    Task {
                        await homeViewModel.handlePrimaryAction()
                    }
                },
                onScanDesktop: {
                    model.recordInteraction(name: "reconnect_tapped", location: "home")
                    Task {
                        await homeViewModel.openScanFlow()
                    }
                }
            )
        case .scanAndPair:
            let pairingViewModel = PairingPageViewModel(model: model)
            PairingFlowView(
                status: pairingViewModel.status,
                scannedQRCodeValue: pairingViewModel.scannedQRCodeBinding,
                onStartPairing: {
                    model.recordInteraction(name: "start_pairing_tapped", location: "pairing")
                    Task {
                        await pairingViewModel.beginPairing()
                    }
                },
                onScanAgain: {
                    model.recordInteraction(name: "scan_again_tapped", location: "pairing")
                    Task {
                        await pairingViewModel.scanAgain()
                    }
                },
                onBack: {
                    model.recordInteraction(name: "back_tapped", location: "pairing")
                    Task {
                        await pairingViewModel.goBack()
                    }
                },
                onOpenSettings: {
                    model.recordInteraction(name: "open_settings_tapped", location: "pairing_scanner")
                }
            )
        case .permissions:
            let permissionsViewModel = PermissionsPageViewModel(model: model)
            PermissionsGateView(
                onStartPreflight: {
                    model.recordInteraction(name: "start_backup_tapped", location: "permissions")
                    Task {
                        await permissionsViewModel.startBackup()
                    }
                }
            )
        case .transfer:
            let transferViewModel = TransferPageViewModel(model: model)
            TransferSessionView(
                snapshot: transferViewModel.snapshot,
                onStop: {
                    model.recordInteraction(name: "stop_backup_tapped", location: "transfer")
                    transferViewModel.requestStopTransfer()
                }
            )
        case .completed:
            let completionViewModel = CompletionPageViewModel(model: model)
            CompletionStateView(
                summary: completionViewModel.summary,
                onReturnHome: {
                    model.recordInteraction(name: "return_home_tapped", location: "completion")
                    Task {
                        await completionViewModel.returnHome()
                    }
                }
            )
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.97, blue: 1.0),   // #F2F8FF
                Color.white,
                Color(red: 0.96, green: 1.0, blue: 0.97),   // #F5FFF8
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var navigationBarBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(red: 0.95, green: 0.97, blue: 1.0),
                Color.white,
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
