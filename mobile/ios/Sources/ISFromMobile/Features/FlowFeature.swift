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
    // State 保持不变
    @ObservableState
    public struct State: Equatable {
        public var destination: Destination?
        
        public init(destination: Destination? = nil) {
            self.destination = destination
        }
    }

    @ObservableState
    @CasePathable
    public enum Destination: Equatable {
        case discover(DiscoverFeature.State)
        case pendingRevisit(PendingRevisitFeature.State)
        case auth(AuthFeature.State)
        case transfer(TransferFeature.State)
        case completion(CompletionFeature.State)
        case error(ErrorFeature.State)
    }

    // Action 直接嵌套，去掉了 PresentationAction 的外壳
    @CasePathable
    public enum Action {
        case onAppear
        case destination(DestinationAction) // 🌟 变直接了
        
        @CasePathable
        public enum DestinationAction {
            case discover(DiscoverFeature.Action)
            case pendingRevisit(PendingRevisitFeature.Action)
            case auth(AuthFeature.Action)
            case transfer(TransferFeature.Action)
            case completion(CompletionFeature.Action)
            case error(ErrorFeature.Action)
        }
    }
    
    @Dependency(\.trustSessionManager) var trustSessionManager
    @Dependency(\.instantShareExtensionContext) var extensionContext
    @Dependency(\.payloadExtractor) var payloadExtractor
    @Dependency(\.identityClient) var identityClient
    @Shared(.instantShareContext) var context
    
    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                if state.destination == nil {
                    state.destination = .discover(DiscoverFeature.State())
                }
                
                return .run { [context = $context, extensionContext, identityClient, payloadExtractor] _ in
                    try? await identityClient.ensureSelfIdentity()

                    let extractTask = await MainActor.run {
                        Task {
                            let inputItems = await extensionContext.getInputItems()
                            return try? await payloadExtractor.extract(inputItems)
                        }
                    }
                    if let envelopes = try? await extractTask.value {
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


            // 🌟 匹配路径变短了，没有了 .presented
            case .destination(.discover(.delegate(.didStartPendingRevisit))):
                state.destination = .pendingRevisit(PendingRevisitFeature.State())
                return .none

            case let .destination(.discover(.delegate(.didEncounterError(message)))):
                state.destination = .error(ErrorFeature.State(message: message))
                return .none

            // 自定义取消按钮事件
            case .destination(.auth(.delegate(.authCancelled))):
                state.destination = nil
                return .none
            
            case .destination(.pendingRevisit(.delegate(.revisitSucceeded(let message)))):
                state.destination = .completion(CompletionFeature.State())
                return .none

            case .destination(.pendingRevisit(.delegate(.revisitFailed))):
                state.destination = .auth(AuthFeature.State())
                return .none

            case .destination(.auth(.delegate(.authCompleted))):
                state.destination = .transfer(TransferFeature.State())
                return .none

            case .destination(.auth(.delegate(.authFailed(let message)))):
                state.destination = .error(ErrorFeature.State(message: message))
                return .none
                
            case .destination(.auth(.delegate(.authCancelled))):
                return .run { [extensionContext] _ in
                    await extensionContext.cancelRequest(error: nil)
                }
                
            case .destination(.transfer(.delegate(.transferSucceeded))):
                state.destination = .completion(CompletionFeature.State())
                return .none
                
            case .destination(.transfer(.delegate(.transferFailed(let message)))):
                state.destination = .error(ErrorFeature.State(message: message))
                return .none
                
            case .destination(.completion(.delegate(.done))):
                return .run { [extensionContext] send in
                    await extensionContext.completeRequest()
                }
                
            case .destination(.error(.delegate(.retry))):
                state.destination = .discover(DiscoverFeature.State())
                return .none
                
            case .destination(.error(.delegate(.cancel))):
                return .run { [extensionContext] send in
                    await extensionContext.cancelRequest(error: nil)
                }
            default:
                return .none
            }
        }
        // 🌟 关键点：这里依然用 .ifLet 绑定，自动取消机制完好无损！
        .ifLet(\.destination, action: \.destination) {
            Scope(state: \.discover, action: \.discover) { DiscoverFeature() }
            Scope(state: \.pendingRevisit, action: \.pendingRevisit) { PendingRevisitFeature() }
            Scope(state: \.auth, action: \.auth) { AuthFeature() }
            Scope(state: \.transfer, action: \.transfer) { TransferFeature() }
            Scope(state: \.completion, action: \.completion) { CompletionFeature() }
            Scope(state: \.error, action: \.error) { ErrorFeature() }
        }
    }
}
