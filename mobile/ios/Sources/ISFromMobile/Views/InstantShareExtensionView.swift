import SwiftUI
import Common

public struct InstantShareExtensionView: View {
    @ObservedObject var viewModel: InstantShareExtensionViewModel
    let onCancel: () -> Void
    let onDone: () -> Void

    public init(viewModel: InstantShareExtensionViewModel, onCancel: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onCancel = onCancel
        self.onDone = onDone
    }

    public var body: some View {
        Group {
            switch viewModel.sessionPhase {
            case .scanning, .ready:
                scanningContent
            case .starting:
                startingContent
            case .awaitingPinInput:
                awaitingPinInputContent
            case .transferring:
                transferringContent
            case .success:
                successContent
            case .failed(let msg):
                failedContent(message: msg)
            }
        }
        .padding()
    }

    // MARK: - Scanning / Ready

    private var scanningContent: some View {
        VStack(spacing: 16) {
            payloadCard
            deviceSelectorCard
            Spacer()
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Button {
                guard viewModel.canSend else { return }
                Task { await viewModel.send() }
            } label: {
                HStack {
                    if viewModel.isProcessing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(viewModel.isProcessing ? "Connecting..." : "Send to \(viewModel.selectedDevice?.name ?? "...")")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.canSend || viewModel.isProcessing)
        }
    }

    // MARK: - Starting

    private var startingContent: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Starting session...")
                .font(.headline)
            Text("Waiting for your Mac to connect")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel", role: .cancel, action: { viewModel.dismissCompletion(); onCancel() })
        }
    }

    // MARK: - Awaiting PIN Input

    private var awaitingPinInputContent: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Enter PIN")
                .font(.title2.bold())
            Text("Enter the 4-digit code shown on your Mac:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            PinCodeInputView(onSubmit: { pinCode in
                viewModel.confirmPIN(pinCode: pinCode)
            })
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button(role: .cancel) {
                viewModel.rejectPIN()
                onCancel()
            } label: {
                Text("Cancel")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Spacer()
        }
    }

    // MARK: - Transferring

    private var transferringContent: some View {
        VStack(spacing: 24) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Sending...")
                .font(.headline)
            Text("Transferring \(payloadDescription) to your Mac")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Success

    private var successContent: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Sent!")
                .font(.title2.bold())
            Text("\(payloadDescription.capitalized) delivered to your Mac")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                viewModel.dismissCompletion()
                onDone()
            } label: {
                Text("Done")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Failed

    private func failedContent(message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("Transfer Failed")
                .font(.title2.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            HStack(spacing: 16) {
                Button {
                    viewModel.dismissCompletion()
                    onCancel()
                } label: {
                    Text("Cancel")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    viewModel.dismissCompletion()
                    viewModel.startDiscovery()
                } label: {
                    Text("Try Again")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Cards

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
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                if !viewModel.discoveredDevices.isEmpty {
                    Text("\(viewModel.discoveredDevices.count) found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if viewModel.discoveredDevices.isEmpty {
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
                ForEach(viewModel.discoveredDevices) { pc in
                    deviceRow(pc)
                }
            }
        }
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

    // MARK: - Helpers

    private var payloadDescription: String {
        switch viewModel.payloadEnvelope?.payloadType {
        case .text: return "text"
        case .image: return "image"
        default: return "file"
        }
    }

    private var payloadIcon: String {
        switch viewModel.payloadEnvelope?.payloadType {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .video: return "video"
        case .file: return "doc"
        case .none: return viewModel.isProcessing ? "arrow.down.circle" : "questionmark.circle"
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
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
        return envelope.contentType ?? ""
    }
}
