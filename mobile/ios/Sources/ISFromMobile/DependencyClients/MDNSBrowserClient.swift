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
    var discoveredDevices: @Sendable () -> AsyncStream<[InstantShareDiscoveredPC]> = {
        AsyncStream { _ in }
    }
}

extension MDNSBrowserClient: DependencyKey {
    static let liveValue = {
        let browser = InstantShareMDNSBrowser()
        return MDNSBrowserClient(
            startBrowsing: { await browser.startBrowsing() },
            stopBrowsing: { await browser.stopBrowsing() },
            discoveredDevices: {
                AsyncStream { continuation in
                    Task { @MainActor in
                        nonisolated(unsafe) let cancellable = browser.objectWillChange
                            .sink { _ in
                                Task { @MainActor in
                                    continuation.yield(browser.discovered)
                                }
                            }
                        continuation.onTermination = { @Sendable _ in
                            Task { @MainActor in
                                cancellable.cancel()
                            }
                        }
                        await browser.startBrowsing()
                    }
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
