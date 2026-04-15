import Factory
import SwiftUI
#if os(iOS)
import UIKit
#endif

@MainActor
public struct AlbumTransporterRootView: View {
    @State private var model: MobileAppModel

    public init(container: Container = .shared) {
        _model = State(initialValue: container.mobileAppModel())
    }

    public var body: some View {
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
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Long transfers are more likely to pause when battery is low. Connect the device to a charger or desktop if you can.")
        }
        .alert("Full media access recommended", isPresented: $model.isShowingMediaAccessAlert) {
#if os(iOS)
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else {
                    return
                }
                UIApplication.shared.open(url)
            }
#endif
            Button("Not now", role: .cancel) {
                Task {
                    await model.continueBackupWithCurrentMediaAccess()
                }
            }
        } message: {
            Text(model.mediaAccessAlertMessage)
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
                summary: permissionsViewModel.summary,
                removeAfterBackupEnabled: permissionsViewModel.removeAfterBackupEnabled,
                onRemoveAfterBackupChanged: { isEnabled in
                    permissionsViewModel.setRemoveAfterBackupEnabled(isEnabled)
                },
                onContinue: {
                    Task {
                        await permissionsViewModel.startBackup()
                    }
                },
                onBack: {
                    Task {
                        await permissionsViewModel.goBack()
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
