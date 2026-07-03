//
//  DiscoverFeature.swift
//  ISFromMobile
//
//  mDNS device discovery, device selection, payload display, and Send action.
//  Replaces the scanning/ready/starting phases.
//
import ComposableArchitecture
import Common
import Foundation

@Reducer
public struct DiscoverFeature {
    public init() {}

    @ObservableState
    public struct State: Equatable {
        public var discoveredDevices: [InstantShareDiscoveredPC] = []
        public var selectedDevice: InstantShareDiscoveredPC? = nil
        public var errorMessage: String? = nil
        public var isProcessing: Bool = false
        var preWarmStates: [String: Bool] = [:]

        public init(
            discoveredDevices: [InstantShareDiscoveredPC] = [],
            selectedDevice: InstantShareDiscoveredPC? = nil,
            errorMessage: String? = nil,
            isProcessing: Bool = false
        ) {
            self.discoveredDevices = discoveredDevices
            self.selectedDevice = selectedDevice
            self.errorMessage = errorMessage
            self.isProcessing = isProcessing
        }
    }

    @CasePathable
    public enum Action {
        case onAppear
        case stopDiscovery
        case devicesUpdated([InstantShareDiscoveredPC])
        case selectDevice(InstantShareDiscoveredPC)
        case send
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable {
            case didStartPendingRevisit
            case didEncounterError(String)
        }
    }

    @Shared(.instantShareContext) var context
    @Dependency(\.mdnsBrowser) var mdnsBrowser
    @Dependency(\.identityClient) var identityClient

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                // Re-init session ID for a fresh session
                $context.withLock { $0.sessionId = UUID().uuidString.lowercased() }
                state.isProcessing = false
                let browser = mdnsBrowser

                return .run { send in
                    // Start mDNS discovery and stream devices
                    for await devices in browser.discoveredDevices() {
                        await send(.devicesUpdated(devices))
                    }
                }

            case .stopDiscovery:
                let browser = mdnsBrowser
                return .run { _ in
                    await browser.stopBrowsing()
                }

            case .devicesUpdated(let devices):
                state.discoveredDevices = devices
                let needPreWarm = devices.filter({ state.preWarmStates[$0.id] != true })
                for device in devices {
                    state.preWarmStates[device.id] = true
                }
                return .run { _ in
                    // Fire lightweight requests to all IPs to trigger iOS local network permission
                    await withTaskGroup(of: Void.self) { group in
                        for device in needPreWarm {
                            for host in device.hosts {
                                guard let url = URL(string: "http://\(host):\(device.port)/") else { continue }
                                group.addTask {
                                    var request = URLRequest(url: url)
                                    request.timeoutInterval = 2
                                    _ = try? await URLSession.shared.data(for: request)
                                }
                            }
                        }
                    }
                }

            case .selectDevice(let device):
                state.selectedDevice = device
                $context.withLock { $0.targetDevice = device }
                return .none

            case .send:
                // targetDevice set from selectDevice; sessionId reinit from onAppear
                // Payload is already loaded by FlowFeature into context.sharedItems
                return .send(.delegate(.didStartPendingRevisit))

            case .delegate:
                return .none
            }
        }
    }
}
