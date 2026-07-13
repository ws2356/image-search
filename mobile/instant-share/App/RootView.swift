import SwiftUI
import ISDeviceManagement
import ISFromPC
import ISFromMobile
import ComposableArchitecture
import Common

@Reducer
struct RootFeature: Sendable {
    @ObservableState
    struct State: Equatable {
        var deviceManagement: DeviceManagementFeature.State = .init()
        @Presents var sheetContent: ShareSheetContent?
        var hasCompletedSession: Bool = false
    }

    @CasePathable
    enum Action {
        case deviceManagement(DeviceManagementFeature.Action)
        case sheetContent(PresentationAction<Never>)
        case scanButtonTapped
        case receivedSharePayload(QRClaimPayload)
        case onAppear
    }

    @Dependency(\.sharedStorage) var sharedStorage
    @Dependency(\.identityClient) var identityClient

    var body: some ReducerOf<Self> {
        Scope(state: \.deviceManagement, action: \.deviceManagement) {
            DeviceManagementFeature()
        }
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.hasCompletedSession = sharedStorage.hasCompletedSession()
                return .run { _ in
                    try await identityClient.initialize()
                }

            case .scanButtonTapped:
                state.sheetContent = .scan
                return .none

            case .receivedSharePayload(let payload):
                state.sheetContent = .claim(payload)
                return .none

            case .sheetContent(.dismiss):
                state.sheetContent = nil
                state.hasCompletedSession = sharedStorage.hasCompletedSession()
                return .none

            case .deviceManagement:
                return .none
            }
        }
    }
}

struct QRSheetNavigator: Navigator {
    let dismiss: () -> Void
    func requestExit() {
        dismiss()
    }
}

enum ShareSheetContent: Equatable, Identifiable {
    case scan
    case claim(QRClaimPayload)

    var id: String {
        switch self {
        case .scan: return "scan"
        case .claim(let payload): return payload.id
        }
    }
}

struct RootView: View {
    let store: StoreOf<RootFeature>

    var body: some View {
        WithPerceptionTracking {
            let sheetObserved = store.sheetContent
            NavigationView {
                if store.hasCompletedSession {
                    DeviceManagementView(
                        store: store.scope(state: \.deviceManagement, action: \.deviceManagement)
                    )
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(action: { store.send(.scanButtonTapped) }) {
                                Image(systemName: "qrcode.viewfinder")
                            }
                        }
                    }
                } else {
                    UserInstructionView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button(action: { store.send(.scanButtonTapped) }) {
                                    Image(systemName: "qrcode.viewfinder")
                                }
                            }
                        }
                }
            }
            .navigationViewStyle(.stack)
            .task { store.send(.onAppear) }
            .fullScreenCover(
                item: Binding(
                    get: { sheetObserved },
                    set: { if $0 == nil { store.send(.sheetContent(.dismiss)) } }
                )
            ) { content in
                switch content {
                case .scan:
                    ISQRRootView(navigator: QRSheetNavigator(dismiss: { store.send(.sheetContent(.dismiss)) }))
                case .claim(let payload):
                    ISQRRootView(
                        qrPayload: payload,
                        navigator: QRSheetNavigator(dismiss: { store.send(.sheetContent(.dismiss)) })
                    )
                }
            }
        }
    }
}
