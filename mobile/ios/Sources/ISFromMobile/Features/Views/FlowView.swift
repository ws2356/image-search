//
//  FlowView.swift
//  ISFromMobile
//
//  Switches on the route enum and renders the appropriate child view.
//  Manages child store scoping via IfLetStore over @Presents optionals.
//
import SwiftUI
import ComposableArchitecture

public struct FlowView: View {
    @Shared(.instantShareContext) var context
    public let store: StoreOf<FlowFeature>

    public init(store: StoreOf<FlowFeature>) {
        self.store = store
    }

    public var body: some View {
        Group {
            switch store.state.route {
            case .discover:
                IfLetStore(store.scope(state: \.discover, action: \.discover)) { childStore in
                    DiscoverView(store: childStore)
                }
            case .pendingRevisit:
                IfLetStore(store.scope(state: \.pendingRevisit, action: \.pendingRevisit)) { childStore in
                    PendingRevisitView(store: childStore)
                }
            case .auth:
                IfLetStore(store.scope(state: \.auth, action: \.auth)) { childStore in
                    AuthView(store: childStore)
                }
            case .transfer:
                IfLetStore(store.scope(state: \.transfer, action: \.transfer)) { childStore in
                    TransferView(store: childStore)
                }
            case .completion:
                IfLetStore(store.scope(state: \.completion, action: \.completion)) { childStore in
                    CompletionView(store: childStore)
                }
            case .error:
                IfLetStore(store.scope(state: \.error, action: \.error)) { childStore in
                    ErrorView(store: childStore)
                }
            case nil:
                EmptyView()
            }
        }
        .task { store.send(.onAppear) }
    }
}
