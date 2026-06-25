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
struct DiscoverFeature {
    @ObservableState
    struct State: Equatable {
        var discoveredDevices: [InstantShareDiscoveredPC] = []
        var selectedDevice: InstantShareDiscoveredPC? = nil
        var errorMessage: String? = nil
        var isProcessing: Bool = false
    }

    @CasePathable
    enum Action {
        case onAppear
        case stopDiscovery
        case devicesUpdated([InstantShareDiscoveredPC])
        case selectDevice(InstantShareDiscoveredPC)
        case send
        case preWarmLocalNetwork
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case didStartPendingRevisit
            case didEncounterError(String)
        }
    }

    @Shared(.instantShareContext) var context
    @Dependency(\.mdnsBrowser) var mdnsBrowser
    @Dependency(\.identityClient) var identityClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                // Re-init session ID for a fresh session
                $context.withLock { $0.sessionId = UUID().uuidString.lowercased() }
                state.isProcessing = false

                return .run { send in
                    // Start mDNS discovery and stream devices
                    for await devices in mdnsBrowser.discoveredDevices() {
                        await send(.devicesUpdated(devices))
                    }
                }

            case .stopDiscovery:
                return .run { _ in
                    await mdnsBrowser.stopBrowsing()
                }

            case .devicesUpdated(let devices):
                state.discoveredDevices = devices
                return .none

            case .selectDevice(let device):
                state.selectedDevice = device
                $context.withLock { $0.targetDevice = device }
                return .send(.preWarmLocalNetwork)

            case .preWarmLocalNetwork:
                guard let device = state.selectedDevice else { return .none }
                return .run { _ in
                    // Fire lightweight requests to all IPs to trigger iOS local network permission
                    await withTaskGroup(of: Void.self) { group in
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
