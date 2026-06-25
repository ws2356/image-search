//
//  InstantShareExtensionContextClient.swift
//  ISFromMobile
//
//  TCA dependency client wrapping the UIKit extensionContext.
//  Set as a module-level static before store creation via
//  ShareViewController.viewDidLoad. Replaces all onCancel/onDone callback
//  plumbing — any feature can complete or cancel the extension via DI.
//
import ComposableArchitecture
import Foundation

public struct InstantShareExtensionContextClient: @unchecked Sendable {
    public var inputItems: [NSExtensionItem]
    public var completeRequest: @Sendable () -> Void
    public var cancelRequest: @Sendable (Error?) -> Void

    public init(
        inputItems: [NSExtensionItem],
        completeRequest: @escaping @Sendable () -> Void,
        cancelRequest: @escaping @Sendable (Error?) -> Void
    ) {
        self.inputItems = inputItems
        self.completeRequest = completeRequest
        self.cancelRequest = cancelRequest
    }
}

extension InstantShareExtensionContextClient: DependencyKey {
    public static var liveValue: InstantShareExtensionContextClient {
        guard let current else {
            fatalError("InstantShareExtensionContextClient not set — call setup before creating store")
        }
        return current
    }

    nonisolated(unsafe) public static var current: InstantShareExtensionContextClient?
}

extension DependencyValues {
    public var instantShareExtensionContext: InstantShareExtensionContextClient {
        get { self[InstantShareExtensionContextClient.self] }
        set { self[InstantShareExtensionContextClient.self] = newValue }
    }
}
