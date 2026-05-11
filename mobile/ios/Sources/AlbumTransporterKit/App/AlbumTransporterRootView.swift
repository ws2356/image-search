import SwiftUI
import Foundation
import Factory
#if os(iOS)
import UIKit
#endif

@MainActor
public struct AlbumTransporterRootView: View {
    @StateObject private var model: MobileAppModel
    @StateObject private var permissionsViewModel: PermissionsPageViewModel
    @StateObject private var transferViewModel: TransferPageViewModel

    public init() {
        self.init(container: .shared)
    }

    init(container: Container) {
        let model = container.mobileAppModel()
        _model = StateObject(wrappedValue: model)
        _permissionsViewModel = StateObject(
            wrappedValue: PermissionsPageViewModel(model: model)
        )
        _transferViewModel = StateObject(
            wrappedValue: TransferPageViewModel(model: model)
        )
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
            HomeView(viewModel: homeViewModel)
        case .scan:
            let pairingViewModel = PairingPageViewModel(model: model)
            ScanPairingView(viewModel: pairingViewModel)
        case .pair:
            let pairingViewModel = PairingPageViewModel(model: model)
            PairingStatusView(viewModel: pairingViewModel)
        case .permissions:
            PermissionsGateView(viewModel: permissionsViewModel)
        case .transfer:
            TransferSessionView(viewModel: transferViewModel)
        case .completed:
            let completionViewModel = CompletionPageViewModel(model: model)
            CompletionStateView(viewModel: completionViewModel)
        case .error:
            let errorViewModel = ErrorPageViewModel(model: model)
            ErrorStateView(viewModel: errorViewModel)
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
