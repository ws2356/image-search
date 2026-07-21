//
//  CompletionFeature.swift
//  ISFromMobile
//
//  Success confirmation with "Done" button that exits the share extension.
//
import ComposableArchitecture
import Foundation
import Common

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

    @Dependency(\.sharedStorage) var sharedStorage

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .done:
                LocalLog.debug("CompletionFeature done action received")
                sharedStorage.setHasCompletedSession(true)
                return .send(.delegate(.done))
            case .delegate:
                return .none
            }
        }
    }
}
