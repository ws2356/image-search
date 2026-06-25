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
public struct FlowFeature {
    public init() {}

    @ObservableState
    public struct State: Equatable {
        public var discover: DiscoverFeature.State?
        public var pendingRevisit: PendingRevisitFeature.State?
        public var auth: AuthFeature.State?
        public var transfer: TransferFeature.State?
        public var completion: CompletionFeature.State?
        public var error: ErrorFeature.State?

        /// The currently active route — exactly one optional is set at a time.
        public enum Route: Sendable {
            case discover, pendingRevisit, auth, transfer, completion, error
        }

        public var route: Route? {
            if discover != nil { return .discover }
            if pendingRevisit != nil { return .pendingRevisit }
            if auth != nil { return .auth }
            if transfer != nil { return .transfer }
            if completion != nil { return .completion }
            if error != nil { return .error }
            return nil
        }

        public init(
            discover: DiscoverFeature.State? = nil,
            pendingRevisit: PendingRevisitFeature.State? = nil,
            auth: AuthFeature.State? = nil,
            transfer: TransferFeature.State? = nil,
            completion: CompletionFeature.State? = nil,
            error: ErrorFeature.State? = nil
        ) {
            self.discover = discover
            self.pendingRevisit = pendingRevisit
            self.auth = auth
            self.transfer = transfer
            self.completion = completion
            self.error = error
        }
    }

    @CasePathable
    public enum Action {
        case onAppear
        case discover(DiscoverFeature.Action)
        case pendingRevisit(PendingRevisitFeature.Action)
        case auth(AuthFeature.Action)
        case transfer(TransferFeature.Action)
        case completion(CompletionFeature.Action)
        case error(ErrorFeature.Action)
    }

    @Dependency(\.trustSessionManager) var trustSessionManager
    @Dependency(\.instantShareExtensionContext) var extensionContext
    @Dependency(\.payloadExtractor) var payloadExtractor
    @Dependency(\.identityClient) var identityClient
    @Shared(.instantShareContext) var context

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { [context = $context, extensionContext, identityClient, payloadExtractor] _ in
                    try? await identityClient.ensureSelfIdentity()

                    let envelopes = try? await payloadExtractor.extract(extensionContext.inputItems)
                    if let envelopes {
                        context.withLock { value in
                            if let textEnvelope = envelopes.first(where: { $0.payloadType == .text }),
                               let text = textEnvelope.textContent {
                                value.sharedItems = .text(text)
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
                                    value.sharedItems = .images(images)
                                }
                            }
                        }
                    }
                }

            // MARK: - Discover delegate
            case .discover(.delegate(.didStartPendingRevisit)):
                state.discover = nil
                state.pendingRevisit = PendingRevisitFeature.State()
                return .none

            case .discover(.delegate(.didEncounterError(let message))):
                state.discover = nil
                state.error = ErrorFeature.State(message: message)
                return .none

            // MARK: - PendingRevisit delegate
            case .pendingRevisit(.delegate(.revisitSucceeded)):
                state.pendingRevisit = nil
                state.completion = CompletionFeature.State()
                return .none

            case .pendingRevisit(.delegate(.revisitFailed)):
                state.pendingRevisit = nil
                state.auth = AuthFeature.State()
                return .none

            // MARK: - Auth delegate
            case .auth(.delegate(.authCompleted)):
                state.auth = nil
                state.transfer = TransferFeature.State()
                return .none

            case .auth(.delegate(.authFailed(let message))):
                state.auth = nil
                state.error = ErrorFeature.State(message: message)
                return .none

            case .auth(.delegate(.authCancelled)):
                state.auth = nil
                trustSessionManager.reset()
                extensionContext.cancelRequest(nil)
                return .none

            // MARK: - Transfer delegate
            case .transfer(.delegate(.transferSucceeded)):
                state.transfer = nil
                state.completion = CompletionFeature.State()
                return .none

            case .transfer(.delegate(.transferFailed(let message))):
                state.transfer = nil
                state.error = ErrorFeature.State(message: message)
                return .none

            // MARK: - Completion delegate
            case .completion(.delegate(.done)):
                state.completion = nil
                extensionContext.completeRequest()
                return .none

            // MARK: - Error delegate
            case .error(.delegate(.retry)):
                state.error = nil
                state.discover = DiscoverFeature.State()
                return .none

            case .error(.delegate(.cancel)):
                state.error = nil
                extensionContext.cancelRequest(nil)
                return .none

            default:
                return .none
            }
        }
        .ifLet(\.discover, action: \.discover) {
            DiscoverFeature()
        }
        .ifLet(\.pendingRevisit, action: \.pendingRevisit) {
            PendingRevisitFeature()
        }
        .ifLet(\.auth, action: \.auth) {
            AuthFeature()
        }
        .ifLet(\.transfer, action: \.transfer) {
            TransferFeature()
        }
        .ifLet(\.completion, action: \.completion) {
            CompletionFeature()
        }
        .ifLet(\.error, action: \.error) {
            ErrorFeature()
        }
    }
}
