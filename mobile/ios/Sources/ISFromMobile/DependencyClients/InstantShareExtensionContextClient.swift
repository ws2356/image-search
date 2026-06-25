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

public final class InstantShareExtensionContextClient: @unchecked Sendable {
    private weak var context: NSExtensionContext?

    public init(_ context: NSExtensionContext?) {
        self.context = context
    }
    
    @MainActor
    func getInputItems() async -> [NSExtensionItem] {
        if let ret = context?.inputItems as? [NSExtensionItem] {
            return ret
        }
        return []
    }

    @MainActor
    func completeRequest() {
        context?.completeRequest(
            returningItems: nil,
            completionHandler: nil
        )
    }

    @MainActor
    func cancelRequest(error: Error?) {
        let nsError = error ?? NSError(
            domain: "InstantShareExtension",
            code: 0
        )

        context?.cancelRequest(withError: nsError)
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
