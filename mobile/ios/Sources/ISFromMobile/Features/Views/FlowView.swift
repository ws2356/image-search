//
//  FlowView.swift
//  ISFromMobile
//
//  Switches on the route enum and renders the appropriate child view.
//  No NavigationStack, no presentation modifiers — pure content switch.
//
import SwiftUI
import ComposableArchitecture

struct FlowView: View {
    @Shared(.instantShareContext) var context
    let store: StoreOf<FlowFeature>

    var body: some View {
        Group {
            switch store.state.route {
            case .discover:
                if let store = store.scope(state: \.route.discover, action: \.discover) {
                    DiscoverView(store: store)
                }
            case .pendingRevisit:
                if let store = store.scope(state: \.route.pendingRevisit, action: \.pendingRevisit) {
                    PendingRevisitView(store: store)
                }
            case .auth:
                if let store = store.scope(state: \.route.auth, action: \.auth) {
                    AuthView(store: store)
                }
            case .transfer:
                if let store = store.scope(state: \.route.transfer, action: \.transfer) {
                    TransferView(store: store)
                }
            case .completion:
                if let store = store.scope(state: \.route.completion, action: \.completion) {
                    CompletionView(store: store)
                }
            case .error:
                if let store = store.scope(state: \.route.error, action: \.error) {
                    ErrorView(store: store)
                }
            }
        }
        .task { store.send(.onAppear) }
    }
}
