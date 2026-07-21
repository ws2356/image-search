//
//  SharedStorageClient.swift
//  Common
//
//  TCA dependency client wrapping SharedStorageProvider for SnapGet session state.
//

import ComposableArchitecture
import Foundation
import Factory

@DependencyClient
public struct SharedStorageClient: Sendable {
    public var hasCompletedSession: @Sendable () -> Bool = { false }
    public var setHasCompletedSession: @Sendable (Bool) -> Void
}

extension SharedStorageClient: DependencyKey {
    public static let liveValue = SharedStorageClient(
        hasCompletedSession: {
            Container.shared.sharedStorageProvider().hasCompletedSession
        },
        setHasCompletedSession: { newValue in
            var provider = Container.shared.sharedStorageProvider()
            provider.hasCompletedSession = newValue
        }
    )
}

extension DependencyValues {
    public var sharedStorage: SharedStorageClient {
        get { self[SharedStorageClient.self] }
        set { self[SharedStorageClient.self] = newValue }
    }
}
