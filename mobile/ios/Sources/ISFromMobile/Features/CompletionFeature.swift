//
//  CompletionFeature.swift
//  ISFromMobile
//
//  Success confirmation with "Done" button that exits the share extension.
//
import ComposableArchitecture
import Foundation

@Reducer
struct CompletionFeature {
    @ObservableState
    struct State: Equatable {
        let payloadDescription: String
    }

    @CasePathable
    enum Action {
        case done
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case done
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .done:
                return .send(.delegate(.done))
            case .delegate:
                return .none
            }
        }
    }
}
