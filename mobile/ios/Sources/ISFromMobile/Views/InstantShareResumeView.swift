import SwiftUI

struct InstantShareResumeView: View {
    @StateObject var viewModel: InstantShareResumeViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            headerSection
            stateSection
            Spacer()
            actionSection
        }
        .padding(24)
        .onAppear {
            Task { await viewModel.resumeFromHandoff() }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.up.on.square")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
            Text("Instant Share")
                .font(.title2.bold())
            Text("Sending to \(viewModel.deviceName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stateSection: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Preparing...")
                .controlSize(.large)

        case .firstUseTrust(let pin):
            VStack(spacing: 16) {
                Text("Verify this code matches on your Mac:")
                    .font(.subheadline)
                Text(pin)
                    .font(.system(size: 48, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .background(Color.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 16))
            }

        case .trustedDirect:
            ProgressView("Connecting to \(viewModel.deviceName)...")

        case .transferring(let progress):
            VStack(spacing: 12) {
                ProgressView(value: progress) {
                    Text("Sending \(viewModel.payloadDescription)")
                }
                .progressViewStyle(.linear)
            }

        case .delivering:
            ProgressView("Delivering...")

        case .success:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Sent successfully!")
                    .font(.headline)
            }

        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

        case .aborted:
            VStack(spacing: 12) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Share canceled")
                    .font(.headline)
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        switch viewModel.state {
        case .firstUseTrust:
            HStack(spacing: 16) {
                Button("Cancel") { viewModel.rejectPIN() }
                    .buttonStyle(.bordered)
                Button("Code Matches") {
                    Task { await viewModel.confirmPIN() }
                }
                .buttonStyle(.borderedProminent)
            }

        case .transferring:
            Button("Cancel Transfer") { viewModel.abort() }
                .buttonStyle(.bordered)

        case .success, .failed, .aborted:
            Button("Done") {
                viewModel.dismiss()
                onDismiss()
            }
            .buttonStyle(.borderedProminent)

        default:
            EmptyView()
        }
    }
}
