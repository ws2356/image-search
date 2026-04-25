import Factory
import SwiftUI
#if os(iOS)
import UIKit
#endif
import Photos

@MainActor
public struct AlbumTransporterRootView: View {
    @StateObject private var model: MobileAppModel

    public init(container: Container = .shared) {
        _model = StateObject(wrappedValue: container.mobileAppModel())
    }

    public var body: some View {
        navigationContainer
            .background(backgroundGradient)
            .task {
                await model.load()
            }
            .confirmationDialog(
                "Stop backup?",
                isPresented: $model.isShowingStopConfirmation,
                titleVisibility: .visible
            ) {
                Button("Stop Sending More Items", role: .destructive) {
                    Task {
                        await model.confirmStopTransfer()
                    }
                }
                Button("Keep Backing Up", role: .cancel) {}
            } message: {
                Text("The desktop may continue indexing items that already transferred before the stop request.")
            }
            .alert("Low battery detected", isPresented: $model.isShowingLowBatteryWarning) {
                Button("Continue Anyway") {
                    Task {
                        await model.continuePastLowBatteryWarning()
                    }
                }
                Button("Not Now", role: .cancel) {
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
                    Task {
                        await model.continueBackupFromMediaAccess()
                    }
                }
            } message: {
                Text(model.mediaAccessAlertMessage)
            }
            .alert("After backup, remove transferred media?", isPresented: $model.isShowingRemoveAfterBackupPrompt) {
                Button("Remove") {
                    Task {
                        await model.selectRemoveAfterBackupPreferenceAndContinue(true)
                    }
                }
                Button("Do not remove", role: .cancel) {
                    Task {
                        await model.selectRemoveAfterBackupPreferenceAndContinue(false)
                    }
                }
            } message: {
                Text("Choose whether successfully transferred photos and videos should be moved to Recently Removed on this device after backup completes.")
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
                    Task {
                        await homeViewModel.handlePrimaryAction()
                    }
                },
                onScanDesktop: {
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
                    Task {
                        await pairingViewModel.beginPairing()
                    }
                },
                onScanAgain: {
                    Task {
                        await pairingViewModel.scanAgain()
                    }
                },
                onBack: {
                    Task {
                        await pairingViewModel.goBack()
                    }
                }
            )
        case .permissions:
            let permissionsViewModel = PermissionsPageViewModel(model: model)
            PermissionsGateView(
                onStartPreflight: {
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
                    transferViewModel.requestStopTransfer()
                }
            )
        case .completed:
            let completionViewModel = CompletionPageViewModel(model: model)
            CompletionStateView(
                summary: completionViewModel.summary,
                onReturnHome: {
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
