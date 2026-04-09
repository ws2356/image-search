import Factory
import SwiftUI

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
                .background(backgroundGradient)
                .navigationTitle(model.navigationTitle)
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
        }
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
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch model.route {
        case .home:
            HomeView(
                summary: model.homeSummary,
                onPrimaryAction: {
                    Task {
                        await model.handleHomePrimaryAction()
                    }
                },
                onScanDesktop: {
                    Task {
                        await model.openScanFlow()
                    }
                }
            )
        case .scanAndPair:
            PairingFlowView(
                status: model.pairingStatus,
                onStartPairing: {
                    Task {
                        await model.beginPairing()
                    }
                },
                onShowExpired: {
                    model.showExpiredQRCode()
                },
                onBack: {
                    Task {
                        await model.returnHome()
                    }
                }
            )
        case .permissions:
            PermissionsGateView(
                summary: model.permissionSummary,
                onContinue: {
                    Task {
                        await model.startBackup()
                    }
                },
                onBack: {
                    Task {
                        await model.returnHome()
                    }
                }
            )
        case .transfer:
            TransferSessionView(
                snapshot: model.transferSnapshot,
                onStop: {
                    model.requestStopTransfer()
                },
                onSimulateCompletion: {
                    Task {
                        await model.completeTransfer()
                    }
                }
            )
        case .interrupted:
            InterruptedSessionView(
                reason: model.interruptionReason,
                onResume: {
                    Task {
                        await model.resumeTransfer()
                    }
                },
                onReturnHome: {
                    Task {
                        await model.returnHome()
                    }
                }
            )
        case .completed:
            CompletionStateView(
                summary: model.completionSummary,
                onReturnHome: {
                    Task {
                        await model.returnHome()
                    }
                }
            )
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color.indigo.opacity(0.20),
                Color.blue.opacity(0.08),
                Color.clear,
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
