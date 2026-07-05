import ComposableArchitecture
import Foundation

@Reducer
public struct DeviceManagementFeature: Sendable {
    public init() {}

    @ObservableState
    public struct State: Equatable {
        public var trustedDevices: [TrustedDevice] = []
        public var isLoading: Bool = false
        public var isRefreshing: Bool = false
        public var errorMessage: String? = nil

        public init(
            trustedDevices: [TrustedDevice] = [],
            isLoading: Bool = false,
            isRefreshing: Bool = false,
            errorMessage: String? = nil
        ) {
            self.trustedDevices = trustedDevices
            self.isLoading = isLoading
            self.isRefreshing = isRefreshing
            self.errorMessage = errorMessage
        }
    }

    @CasePathable
    public enum Action {
        case onAppear
        case pullToRefresh
        case deleteDevice(TrustedDevice)
        case devicesLoaded([TrustedDevice])
        case deviceDeleteFailed(TrustedDevice, String)
        case clearError
    }

    @Dependency(\.deviceManagement) var deviceManagement

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = true
                state.errorMessage = nil
                return .run { send in
                    try? await deviceManagement.ensureSelfIdentity()
                    let devices = try await deviceManagement.loadDevices()
                    await send(.devicesLoaded(devices))
                } catch: { error, send in
                    await send(.devicesLoaded([]))
                }

            case .pullToRefresh:
                state.isRefreshing = true
                state.errorMessage = nil
                return .run { send in
                    let devices = try await deviceManagement.loadDevices()
                    await send(.devicesLoaded(devices))
                } catch: { error, send in
                    await send(.devicesLoaded([]))
                }

            case .devicesLoaded(let devices):
                state.isLoading = false
                state.isRefreshing = false
                state.trustedDevices = devices
                return .none

            case .deleteDevice(let device):
                state.trustedDevices.removeAll { $0.id == device.id }
                return .run { send in
                    try await deviceManagement.deleteDevice(device.pubkeyHash)
                } catch: { error, send in
                    await send(.deviceDeleteFailed(device, error.localizedDescription))
                }

            case .deviceDeleteFailed(let device, let message):
                state.trustedDevices.append(device)
                state.trustedDevices.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                state.errorMessage = message
                return .none

            case .clearError:
                state.errorMessage = nil
                return .none
            }
        }
    }
}
