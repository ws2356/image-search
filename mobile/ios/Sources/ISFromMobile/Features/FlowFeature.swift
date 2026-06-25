//
//  FlowFeature.swift
//  ISFromMobile
//
//  Coordinator/router — owns the Route enum and shared context.
//  Transitions between child features based on delegate actions.
//  Owns @Shared(.instantShareContext) — loads shared items from extension
//  context on appear.
//
import ComposableArchitecture
import Common
import Foundation

@Reducer
struct FlowFeature {
    @ObservableState
    struct State: Equatable {
        var route: Route

        @CasePathable
        enum Route: Equatable {
            case discover(DiscoverFeature.State)
            case pendingRevisit(PendingRevisitFeature.State)
            case auth(AuthFeature.State)
            case transfer(TransferFeature.State)
            case completion(CompletionFeature.State)
            case error(ErrorFeature.State)
        }
    }

    @CasePathable
    enum Action {
        case onAppear
        case discover(DiscoverFeature.Action)
        case pendingRevisit(PendingRevisitFeature.Action)
        case auth(AuthFeature.Action)
        case transfer(TransferFeature.Action)
        case completion(CompletionFeature.Action)
        case error(ErrorFeature.Action)
    }

    @Shared(.instantShareContext) var context
    @Dependency(\.payloadExtractor) var payloadExtractor
    @Dependency(\.identityClient) var identityClient
    @Dependency(\.trustSessionManager) var trustSessionManager
    @Dependency(\.instantShareExtensionContext) var extensionContext

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { [context = context] send in
                    try? await identityClient.ensureSelfIdentity()

                    let envelopes = try? await payloadExtractor.extract(extensionContext.inputItems)
                    if let envelopes {
                        await context.$sharedItems.withLock { sharedItems in
                            if let textEnvelope = envelopes.first(where: { $0.payloadType == .text }),
                               let text = textEnvelope.textContent {
                                sharedItems = .text(text)
                            } else {
                                let images = envelopes
                                    .filter { $0.payloadType == .image }
                                    .compactMap { env -> SharedImage? in
                                        guard let url = env.fileURL else { return nil }
                                        return SharedImage(
                                            fileURL: url,
                                            filename: env.filename ?? "image",
                                            contentType: env.contentType ?? "image/jpeg"
                                        )
                                    }
                                if !images.isEmpty {
                                    sharedItems = .images(images)
                                }
                            }
                        }
                    }
                }

            // MARK: - Discover delegate → PendingRevisit
            case .discover(.delegate(.didStartPendingRevisit)):
                state.route = .pendingRevisit(PendingRevisitFeature.State(
                    payloadDescription: payloadDescription(from: context.sharedItems)
                ))
                return .none

            case .discover(.delegate(.didEncounterError(let message))):
                state.route = .error(ErrorFeature.State(message: message))
                return .none

            // MARK: - PendingRevisit delegate
            case .pendingRevisit(.delegate(.revisitSucceeded(let desc))):
                state.route = .completion(CompletionFeature.State(payloadDescription: desc))
                return .none

            case .pendingRevisit(.delegate(.revisitFailed)):
                state.route = .auth(AuthFeature.State())
                return .none

            // MARK: - Auth delegate
            case .auth(.delegate(.authCompleted)):
                state.route = .transfer(TransferFeature.State())
                return .none

            case .auth(.delegate(.authFailed(let message))):
                state.route = .error(ErrorFeature.State(message: message))
                return .none

            case .auth(.delegate(.authCancelled)):
                trustSessionManager.reset()
                extensionContext.cancelRequest(nil)
                return .none

            // MARK: - Transfer delegate
            case .transfer(.delegate(.transferSucceeded)):
                state.route = .completion(CompletionFeature.State(
                    payloadDescription: payloadDescription(from: context.sharedItems)
                ))
                return .none

            case .transfer(.delegate(.transferFailed(let message))):
                state.route = .error(ErrorFeature.State(message: message))
                return .none

            // MARK: - Completion delegate
            case .completion(.delegate(.done)):
                extensionContext.completeRequest()
                return .none

            // MARK: - Error delegate
            case .error(.delegate(.retry)):
                context = InstantShareContext()
                state.route = .discover(DiscoverFeature.State())
                return .none

            case .error(.delegate(.cancel)):
                extensionContext.cancelRequest(nil)
                return .none

            // MARK: - Forward non-delegate actions to child reducers
            case .discover(let childAction):
                return forwardChildReduce(
                    into: &state,
                    childAction: childAction,
                    extract: (/State.Route.discover).extract,
                    embed: State.Route.discover,
                    embedAction: Action.discover,
                    childReducer: DiscoverFeature()
                )

            case .pendingRevisit(let childAction):
                return forwardChildReduce(
                    into: &state,
                    childAction: childAction,
                    extract: (/State.Route.pendingRevisit).extract,
                    embed: State.Route.pendingRevisit,
                    embedAction: Action.pendingRevisit,
                    childReducer: PendingRevisitFeature()
                )

            case .auth(let childAction):
                return forwardChildReduce(
                    into: &state,
                    childAction: childAction,
                    extract: (/State.Route.auth).extract,
                    embed: State.Route.auth,
                    embedAction: Action.auth,
                    childReducer: AuthFeature()
                )

            case .transfer(let childAction):
                return forwardChildReduce(
                    into: &state,
                    childAction: childAction,
                    extract: (/State.Route.transfer).extract,
                    embed: State.Route.transfer,
                    embedAction: Action.transfer,
                    childReducer: TransferFeature()
                )

            case .completion(let childAction):
                return forwardChildReduce(
                    into: &state,
                    childAction: childAction,
                    extract: (/State.Route.completion).extract,
                    embed: State.Route.completion,
                    embedAction: Action.completion,
                    childReducer: CompletionFeature()
                )

            case .error(let childAction):
                return forwardChildReduce(
                    into: &state,
                    childAction: childAction,
                    extract: (/State.Route.error).extract,
                    embed: State.Route.error,
                    embedAction: Action.error,
                    childReducer: ErrorFeature()
                )
            }
        }
    }

    // MARK: - Helpers

    /// Forward a child action to the child reducer when the current route matches.
    private func forwardChildReduce<ChildState: Equatable, ChildAction, ChildReducer: Reducer>(
        into state: inout State,
        childAction: ChildAction,
        extract: (State.Route) -> ChildState?,
        embed: @escaping (ChildState) -> State.Route,
        embedAction: @escaping (ChildAction) -> Action,
        childReducer: ChildReducer
    ) -> Effect<Action> where ChildReducer.State == ChildState, ChildReducer.Action == ChildAction {
        guard var childState = extract(state.route) else { return .none }
        let effect = childReducer.reduce(into: &childState, action: childAction)
        state.route = embed(childState)
        return effect.map(embedAction)
    }

    private func payloadDescription(from sharedItems: SharedItems) -> String {
        switch sharedItems {
        case .text: return "text"
        case .images(let images): return images.count > 1 ? "\(images.count) images" : "image"
        case .files: return "file"
        }
    }
}
