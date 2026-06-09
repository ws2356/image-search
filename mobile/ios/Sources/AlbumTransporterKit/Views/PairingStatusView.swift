import SwiftUI
import Common

struct PairingStatusView: View {
    @ObservedObject var viewModel: PairingPageViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                pairingHero
                pairingStepStatus

                Button {
                    Task {
                        await viewModel.backTapped()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                        Text("Cancel")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(Color(hex: 0xFF453A))
                    .background(Color(hex: 0xFFF1F0))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .compatibleScrollBounceBasedOnSize()
        .appNavigationBar(title: "Pairing")
        .task {
            await viewModel.orchestratePairing()
        }
    }

    private var pairingHero: some View {
        VStack(spacing: 12) {
            ZStack {
                ForEach(0..<3, id: \.self) { ring in
                    Circle()
                        .stroke(Color(hex: 0x007AFF).opacity(0.15 + Double(ring) * 0.05), lineWidth: 2)
                        .frame(width: 120 + CGFloat(ring) * 24, height: 120 + CGFloat(ring) * 24)
                }

                heroCircle(
                    icon: "lock.shield",
                    gradient: [Color(hex: 0x007AFF), Color(hex: 0x0055D4)]
                )
            }

            Text("Connecting…")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color(hex: 0x1C1C1E))

            Text(pairingMessage)
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var pairingStepStatus: some View {
        VStack(spacing: 0) {
            stepStatusRow(icon: "checkmark.circle.fill", iconColor: Color(hex: 0x30D158), text: "QR code scanned")
            Divider().padding(.leading, 42)
            stepStatusRow(icon: "checkmark.circle.fill", iconColor: Color(hex: 0x30D158), text: "Desktop reached")
            Divider().padding(.leading, 42)
            HStack(spacing: 12) {
                ProgressView()
                    .frame(width: 20, height: 20)
                Text("Verifying trust material…")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }

    private func stepStatusRow(icon: String, iconColor: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: 0x1C1C1E))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var pairingMessage: String {
        "Validating the QR payload and establishing a secure local session with the desktop."
    }
}
