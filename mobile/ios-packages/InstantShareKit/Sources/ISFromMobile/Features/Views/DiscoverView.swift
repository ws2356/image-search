//
//  DiscoverView.swift
//  ISFromMobile
//
//  mDNS device discovery: empty, scanning, and found states.
//  Uses DesignSystem tokens and shared Components for consistent styling.
//
import SwiftUI
import ComposableArchitecture

#if os(iOS)
struct DiscoverView: View {
    let store: StoreOf<DiscoverFeature>
    @Shared(.instantShareContext) var context

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: DesignSystem.Spacing.xl) {
                payloadCard
                deviceSelectorCard
                Spacer()
                if let error = store.errorMessage {
                    DSText(text: error, style: .caption, color: DesignSystem.Colors.error)
                }
                PrimaryButton(
                    title: store.isProcessing ? "Connecting..." : "Send to \(store.selectedDevice?.name ?? "...")",
                    style: .primary,
                    isLoading: store.isProcessing,
                    action: { store.send(.send) }
                )
                .disabled(!(store.selectedDevice != nil && !context.isLoadingSharedItems && !store.isProcessing))
            }
            .padding(DesignSystem.Spacing.xl)
            .background(Color(.systemBackground))
            .task { store.send(.onAppear) }
        }
    }

    // MARK: - Payload Card

    private var payloadCard: some View {
        WithPerceptionTracking {
            CardView {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: payloadIcon)
                        .font(.title2)
                        .foregroundStyle(DesignSystem.Colors.primary)
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        DSText(text: payloadTitle, style: .h4)
                        DSText(text: payloadSubtitle, style: .caption)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Device Selector

    private var deviceSelectorCard: some View {
        WithPerceptionTracking {
            CardView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    HStack {
                        DSText(text: "Send to", style: .h4)
                        Spacer()
                        if !store.discoveredDevices.isEmpty {
                            DSText(
                                text: "\(store.discoveredDevices.count) found",
                                style: .caption,
                                color: DesignSystem.Colors.success
                            )
                        }
                    }

                    if store.discoveredDevices.isEmpty {
                        // Empty / scanning state
                        VStack(spacing: DesignSystem.Spacing.md) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(DesignSystem.Colors.primary)
                            ScanningBadge()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.lg)
                    } else {
                        // Found state: device list
                        ForEach(store.discoveredDevices) { pc in
                            deviceRow(pc)
                        }
                    }
                }
            }
        }
    }

    private func deviceRow(_ device: InstantShareDiscoveredPC) -> some View {
        WithPerceptionTracking {
            Button {
                store.send(.selectDevice(device))
            } label: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "laptopcomputer")
                        .foregroundStyle(DesignSystem.Colors.primary)
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        DSText(text: device.name, style: .body)
                        DSText(text: "\(device.primaryHost):\(device.port)", style: .caption2)
                    }
                    Spacer()
                    Image(systemName: store.selectedDevice?.id == device.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(
                            store.selectedDevice?.id == device.id
                            ? DesignSystem.Colors.primary
                            : DesignSystem.Colors.secondaryText.opacity(0.4)
                        )
                }
                .padding(DesignSystem.Spacing.md)
                .background(
                    store.selectedDevice?.id == device.id
                    ? DesignSystem.Colors.selectedHighlight
                    : Color.clear,
                    in: RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.chip)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Payload Helpers

    private var payloadIcon: String {
        switch context.sharedItems {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .images: return "photo"
        case .files: return "doc"
        }
    }

    private var payloadTitle: String {
        switch context.sharedItems {
        case .text(let text):
            return text.count > 50 ? String(text.prefix(50)) + "..." : text
        case .link(let url):
            return url.count > 60 ? String(url.prefix(60)) + "..." : url
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
        case .link(let url):
            return url
        case .images(let images):
            return images.count > 1 ? "\(images.count) images" : "1 image"
        case .files:
            return "File"
        }
    }
}
#endif
