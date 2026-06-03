import SwiftUI

public struct InstantShareExtensionView: View {
    @ObservedObject var viewModel: InstantShareExtensionViewModel
    let onCancel: () -> Void
    let onSend: () -> Void

    public init(viewModel: InstantShareExtensionViewModel, onCancel: @escaping () -> Void, onSend: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onCancel = onCancel
        self.onSend = onSend
    }

    public var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    content
                }
            } else {
                NavigationView {
                    content
                }
            }
        }
    }

    private var content: some View {
        VStack(spacing: 16) {
            payloadCard
            deviceSelectorCard
            Spacer()
            actionBar
        }
        .padding()
        .navigationTitle("Instant Share")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }

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

    private var deviceSelectorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Send to")
                    .font(.headline)
                Spacer()
                if viewModel.scannerState == "scanning" {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if viewModel.discoveredDevices.isEmpty {
                emptyDevicesView
            } else {
                ForEach(viewModel.discoveredDevices) { device in
                    deviceRow(device)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyDevicesView: some View {
        VStack(spacing: 8) {
            Image(systemName: "desktopcomputer")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(viewModel.scannerState == "scanning"
                 ? "Looking for nearby Macs..."
                 : "No Macs found. Make sure AuSearch is running.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func deviceRow(_ device: InstantShareDiscoveredPC) -> some View {
        Button {
            viewModel.selectDevice(device)
        } label: {
            HStack {
                Image(systemName: "laptopcomputer")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text(device.name)
                        .font(.body)
                    Text("\(device.host):\(device.port)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.selectedDevice?.id == device.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                viewModel.selectedDevice?.id == device.id
                    ? Color.blue.opacity(0.1)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
    }

    private var actionBar: some View {
        HStack {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                do {
                    try viewModel.performHandoff()
                    onSend()
                } catch {
                    viewModel.errorMessage = error.localizedDescription
                }
            } label: {
                Text("Send")
                    .fontWeight(.semibold)
                    .frame(minWidth: 80)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.selectedDevice == nil || viewModel.payloadEnvelope == nil)
        }
    }

    private var payloadIcon: String {
        switch viewModel.payloadEnvelope?.payloadType {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .video: return "video"
        case .file: return "doc"
        case .none: return "questionmark.circle"
        }
    }

    private var payloadTitle: String {
        guard let envelope = viewModel.payloadEnvelope else {
            return viewModel.isProcessing ? "Loading..." : "No content"
        }
        switch envelope.payloadType {
        case .text:
            let preview = envelope.textContent ?? ""
            return preview.count > 50 ? String(preview.prefix(50)) + "..." : preview
        case .image: return "Image"
        case .video: return "Video"
        case .file: return envelope.filename ?? "File"
        }
    }

    private var payloadSubtitle: String {
        guard let envelope = viewModel.payloadEnvelope else { return "" }
        if let size = envelope.fileSizeBytes {
            return "\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
        }
        return envelope.contentType ?? ""
    }
}
