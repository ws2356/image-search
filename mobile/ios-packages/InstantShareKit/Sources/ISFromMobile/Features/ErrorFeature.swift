//
//  ErrorFeature.swift
//  ISFromMobile
//
//  Full-screen error display with Retry → Discovery and Cancel → exit.
//
import ComposableArchitecture
import Foundation

@Reducer
public struct ErrorFeature {
    @ObservableState
    public struct State: Equatable {
        public let message: String

        public init(message: String = "") {
            self.message = message
        }
    }

    @CasePathable
    public enum Action {
        case retry
        case cancel
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable {
            case retry
            case cancel
        }
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .retry:
                return .send(.delegate(.retry))
            case .cancel:
                return .send(.delegate(.cancel))
            case .delegate:
                return .none
            }
        }
    }
}
