import SwiftUI
import ISDeviceManagement
import ISFromPC
import ComposableArchitecture

@Reducer
struct RootFeature: Sendable {
    @ObservableState
    struct State: Equatable {
        var deviceManagement: DeviceManagementFeature.State = .init()
        var sheetContent: ShareSheetContent?
    }

    @CasePathable
    enum Action {
        case deviceManagement(DeviceManagementFeature.Action)
        case scanButtonTapped
        case receivedSharePayload(QRClaimPayload)
        case dismissSheet
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.deviceManagement, action: \.deviceManagement) {
            DeviceManagementFeature()
        }
        Reduce { state, action in
            switch action {
            case .scanButtonTapped:
                state.sheetContent = .scan
                return .none

            case .receivedSharePayload(let payload):
                state.sheetContent = .claim(payload)
                return .none

            case .dismissSheet:
                state.sheetContent = nil
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
    @State private var sheetContent: ShareSheetContent?

    var body: some View {
        WithPerceptionTracking {
            NavigationView {
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
            }
            .navigationViewStyle(.stack)
            .onChange(of: store.sheetContent) { newContent in
                sheetContent = newContent
            }
        }
        .onChange(of: sheetContent) { newContent in
            if newContent == nil {
                store.send(.dismissSheet)
            }
        }
        .fullScreenCover(item: $sheetContent) { content in
            switch content {
            case .scan:
                ISQRRootView(navigator: QRSheetNavigator(dismiss: { store.send(.dismissSheet) }))
            case .claim(let payload):
                ISQRRootView(
                    qrPayload: payload,
                    navigator: QRSheetNavigator(dismiss: { store.send(.dismissSheet) })
                )
            }
        }
    }
}
