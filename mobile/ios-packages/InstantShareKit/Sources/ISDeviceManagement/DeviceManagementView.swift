import SwiftUI
import ComposableArchitecture

#if os(iOS)
public struct DeviceManagementView: View {
    let store: StoreOf<DeviceManagementFeature>

    public init(store: StoreOf<DeviceManagementFeature>) {
        self.store = store
    }

    public var body: some View {
        WithPerceptionTracking {
            List {
                if store.isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if store.trustedDevices.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "externaldrive.badge.questionmark")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No Trusted Devices")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(store.trustedDevices) { device in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(device.name)
                                .font(.body)
                            Text(device.id)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let device = store.trustedDevices[index]
                            store.send(.deleteDevice(device))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Devices")
            .task { await store.send(.onAppear).finish() }
            .overlay(alignment: .bottom) {
                if let error = store.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(12)
                }
            }
        }
    }
}
#endif
