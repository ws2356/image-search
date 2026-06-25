//
//  ErrorFeature.swift
//  ISFromMobile
//
//  Full-screen error display with Retry → Discovery and Cancel → exit.
//
import ComposableArchitecture
import Foundation

@Reducer
struct ErrorFeature {
    @ObservableState
    struct State: Equatable {
        let message: String
    }

    @CasePathable
    enum Action {
        case retry
        case cancel
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case retry
            case cancel
        }
    }

    var body: some ReducerOf<Self> {
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
