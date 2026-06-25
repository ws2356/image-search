//
//  CompletionFeature.swift
//  ISFromMobile
//
//  Success confirmation with "Done" button that exits the share extension.
//
import ComposableArchitecture
import Foundation

@Reducer
public struct CompletionFeature {
    @ObservableState
    public struct State: Equatable {
        public let payloadDescription: String

        public init(payloadDescription: String = "") {
            self.payloadDescription = payloadDescription
        }
    }

    @CasePathable
    public enum Action {
        case done
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable {
            case done
        }
    }

    public var body: some ReducerOf<Self> {
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
