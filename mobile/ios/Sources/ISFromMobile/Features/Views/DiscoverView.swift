//
//  DiscoverView.swift
//  ISFromMobile
//
//  mDNS device discovery, payload card, device selector, Send button.
//
import SwiftUI
import ComposableArchitecture

struct DiscoverView: View {
    let store: StoreOf<DiscoverFeature>
    @Shared(.instantShareContext) var context

    var body: some View {
        VStack(spacing: 16) {
            payloadCard
            deviceSelectorCard
            Spacer()
            if let error = store.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button {
                store.send(.send)
            } label: {
                HStack {
                    if store.isProcessing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(store.isProcessing ? "Connecting..." : "Send to \(store.selectedDevice?.name ?? "...")")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSend)
        }
        .padding()
        .task { store.send(.onAppear) }
    }

    private var canSend: Bool {
        store.selectedDevice != nil && !context.isLoadingSharedItems && !store.isProcessing
    }

    // MARK: - Payload Card

    private var payloadCard: some View {
        HStack {
            Image(systemName: payloadIcon)
                .font(.title2)
                .foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text(payloadTitle)
                    .font(.headline)
                Text(payloadSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Device Selector

    private var deviceSelectorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Send to")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if !store.discoveredDevices.isEmpty {
                    Text("\(store.discoveredDevices.count) found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if store.discoveredDevices.isEmpty {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Looking for desktops...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ForEach(store.discoveredDevices) { pc in
                    deviceRow(pc)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func deviceRow(_ device: InstantShareDiscoveredPC) -> some View {
        Button {
            store.send(.selectDevice(device))
        } label: {
            HStack {
                Image(systemName: "laptopcomputer")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text(device.name)
                        .font(.body)
                    Text("\(device.primaryHost):\(device.port)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: store.selectedDevice?.id == device.id ? "checkmark.square.fill" : "square")
                    .foregroundStyle(store.selectedDevice?.id == device.id ? .green : .gray.opacity(0.4))
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                store.selectedDevice?.id == device.id
                    ? Color.blue.opacity(0.1)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Payload Helpers

    private var payloadIcon: String {
        switch context.sharedItems {
        case .text: return "text.alignleft"
        case .images: return "photo"
        case .files: return "doc"
        }
    }

    private var payloadTitle: String {
        switch context.sharedItems {
        case .text(let text):
            return text.count > 50 ? String(text.prefix(50)) + "..." : text
        case .images(let images):
            return images.count > 1 ? "\(images.count) Images" : "Image"
        case .files:
            return "File"
        }
    }

    private var payloadSubtitle: String {
        switch context.sharedItems {
        case .text(let text):
            return "\(text.count) characters"
        case .images(let images):
            return images.count > 1 ? "\(images.count) images" : "1 image"
        case .files:
            return "File"
        }
    }
}
