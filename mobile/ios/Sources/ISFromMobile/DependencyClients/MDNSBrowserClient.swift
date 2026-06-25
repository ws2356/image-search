//
//  MDNSBrowserClient.swift
//  ISFromMobile
//
//  TCA dependency client wrapping InstantShareMDNSBrowser.
//  Provides an async stream of discovered devices by bridging the browser's Combine publisher.
//
import ComposableArchitecture
import Common
import Foundation

@DependencyClient
struct MDNSBrowserClient {
    var startBrowsing: @Sendable () async -> Void
    var stopBrowsing: @Sendable () async -> Void
    var discoveredDevices: @Sendable () -> AsyncStream<[InstantShareDiscoveredPC>] = {
        AsyncStream { _ in }
    }
}

extension MDNSBrowserClient: DependencyKey {
    static let liveValue = {
        nonisolated(unsafe) let browser = InstantShareMDNSBrowser()
        return MDNSBrowserClient(
            startBrowsing: { browser.startBrowsing() },
            stopBrowsing: { browser.stopBrowsing() },
            discoveredDevices: {
                AsyncStream { continuation in
                    let cancellable = browser.objectWillChange
                        .sink { _ in continuation.yield(browser.discovered) }
                    continuation.onTermination = { _ in cancellable.cancel() }
                    browser.startBrowsing()
                }
            }
        )
    }()
}

extension DependencyValues {
    var mdnsBrowser: MDNSBrowserClient {
        get { self[MDNSBrowserClient.self] }
        set { self[MDNSBrowserClient.self] = newValue }
    }
}
