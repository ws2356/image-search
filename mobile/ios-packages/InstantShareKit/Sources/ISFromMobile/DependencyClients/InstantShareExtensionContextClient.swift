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
import Common

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
    func completeRequest() async {
        context?.completeRequest(
            returningItems: nil,
            completionHandler: nil
        )
    }

    @MainActor
    func cancelRequest(error: Error?) async {
        let nsError = error ?? NSError(
            domain: "InstantShareExtension",
            code: 0
        )

        context?.cancelRequest(withError: nsError)
    }
    
    @MainActor
    func debugPrint(_ tag: String) async {
        if let ctx = context {
            LocalLog.debug("[\(tag)] InstantShareExtensionContextClient \(self), wrapped: \(ctx)")
        }
    }
}

extension InstantShareExtensionContextClient: DependencyKey {
    public static var liveValue: InstantShareExtensionContextClient {
        fatalError("InstantShareExtensionContextClient must be configured as dependency when creating the store")
    }
}

extension DependencyValues {
    public var instantShareExtensionContext: InstantShareExtensionContextClient {
        get { self[InstantShareExtensionContextClient.self] }
        set { self[InstantShareExtensionContextClient.self] = newValue }
    }
}
