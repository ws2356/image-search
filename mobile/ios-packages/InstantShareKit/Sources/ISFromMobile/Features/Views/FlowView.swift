//
//  FlowView.swift
//  ISFromMobile
//
//  Switches on the route enum and renders the appropriate child view.
//  Manages child store scoping via IfLetStore over @Presents optionals.
//
import SwiftUI
import ComposableArchitecture

#if os(iOS)
public struct FlowView: View {
    @Shared(.instantShareContext) var context
    
    public let store: StoreOf<FlowFeature>

    public init(store: StoreOf<FlowFeature>) {
        self.store = store
    }
    
    public var body: some View {
        WithPerceptionTracking {
            Group {
                if let destinationStore = store.scope(state: \.destination, action: \.destination) {
                    SwitchStore(destinationStore) { state in
                        switch state {
                        case .discover:
                            CaseLet(
                                /FlowFeature.Destination.discover,
                                 action: FlowFeature.Action.DestinationAction.discover
                            ) { childStore in
                                DiscoverView(store: childStore)
                            }
                            
                        case .pendingRevisit:
                            CaseLet(
                                /FlowFeature.Destination.pendingRevisit,
                                 action: FlowFeature.Action.DestinationAction.pendingRevisit
                            ) { childStore in
                                PendingRevisitView(store: childStore)
                            }
                            
                        case .auth:
                            CaseLet(
                                /FlowFeature.Destination.auth,
                                 action: FlowFeature.Action.DestinationAction.auth
                            ) { childStore in
                                AuthView(store: childStore)
                            }
                            
                        case .transfer:
                            CaseLet(
                                /FlowFeature.Destination.transfer,
                                 action: FlowFeature.Action.DestinationAction.transfer
                            ) { childStore in
                                TransferView(store: childStore)
                            }
                            
                        case .completion:
                            CaseLet(
                                /FlowFeature.Destination.completion,
                                 action: FlowFeature.Action.DestinationAction.completion
                            ) { childStore in
                                CompletionView(store: childStore)
                            }
                            
                        case .error:
                            CaseLet(
                                /FlowFeature.Destination.error,
                                 action: FlowFeature.Action.DestinationAction.error
                            ) { childStore in
                                ErrorView(store: childStore)
                            }
                        }
                    }
                    
                } else {
                    EmptyView()
                }
            }
            .task { store.send(.onAppear) }
        }
    }
}
#endif
