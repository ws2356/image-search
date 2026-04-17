import SwiftUI

struct PairingFlowView: View {
    let status: PairingStatus
    @Binding var scannedQRCodeValue: String
    let onStartPairing: () -> Void
    let onScanAgain: () -> Void
    let onBack: () -> Void

    var body: some View {
        #if os(iOS)
        if isLiveScanPhase {
            if #available(iOS 16.0, *) {
                LiveQRCodeScannerScreen(
                    status: status,
                    scannedQRCodeValue: $scannedQRCodeValue,
                    onStartPairing: onStartPairing,
                    onBack: onBack
                )
                .toolbar(.hidden, for: .navigationBar)
            } else {
                LiveQRCodeScannerScreen(
                    status: status,
                    scannedQRCodeValue: $scannedQRCodeValue,
                    onStartPairing: onStartPairing,
                    onBack: onBack
                )
                .navigationBarHidden(true)
            }
        } else {
            pairingStateContent
        }
        #else
        pairingStateContent
        #endif
    }

    private var isLiveScanPhase: Bool {
        status.phase == .instructions || status.phase == .scanning
    }

    private var pairingStateContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                pairingHero

                if status.phase == .pairing {
                    pairingStepStatus
                }

                if status.phase == .paired {
                    destinationCard
                }

                if status.phase == .expired {
                    recoveryStepsCard
                }

                VStack(spacing: 10) {
                    if status.phase == .pairing {
                        Button(action: onBack) {
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
                    } else {
                        ActionButton(
                            title: pairingButtonTitle,
                            icon: pairingButtonIcon,
                            style: .primary,
                            action: primaryAction
                        )
                        .disabled(isPrimaryActionDisabled)

                        if status.phase == .failed {
                            ActionButton(title: "Cancel", style: .cancelSecondary, action: onBack)
                        } else if status.phase != .paired {
                            ActionButton(title: "Back", icon: "chevron.left", style: .plain, action: onBack)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .compatibleScrollBounceBasedOnSize()
    }

    @ViewBuilder
    private var pairingHero: some View {
        VStack(spacing: 12) {
            ZStack {
                if status.phase == .pairing {
                    ForEach(0..<3, id: \.self) { ring in
                        Circle()
                            .stroke(Color(hex: 0x007AFF).opacity(0.15 + Double(ring) * 0.05), lineWidth: 2)
                            .frame(width: 120 + CGFloat(ring) * 24, height: 120 + CGFloat(ring) * 24)
                    }
                }

                heroCircle(
                    icon: pairingHeroIcon,
                    gradient: pairingHeroGradient
                )
            }

            Text(pairingTitle)
                .font(.system(size: pairingTitleSize, weight: .bold))
                .foregroundStyle(Color(hex: 0x1C1C1E))

            Text(status.message)
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

    private var destinationCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Backup destination")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .textCase(.uppercase)
                .compatibleKerning(0.5)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                if let desktopName = normalizedDesktopDisplayName(status.desktopName) {
                    infoRow(icon: "desktopcomputer", label: "PC", value: desktopName)
                    Divider().padding(.leading, 42)
                }
                if let sessionID = status.sessionID {
                    infoRow(icon: "folder", label: "Folder", value: sessionID)
                    Divider().padding(.leading, 42)
                }
                if let transport = status.transport {
                    infoRow(icon: transport.systemImage, label: "Transport", value: transport.title)
                }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }

    private var recoveryStepsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            numberedRecoveryStep(number: "1", title: "Refresh on PC", detail: "Generate a new QR code from the desktop app")
            Divider().padding(.leading, 56)
            numberedRecoveryStep(number: "2", title: "Scan Again", detail: "Use the button below to scan the new code")
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }

    private func numberedRecoveryStep(number: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: 0x007AFF))
                    .frame(width: 28, height: 28)
                Text(number)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x6E6E73))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color(hex: 0x6E6E73))
                .frame(width: 20)
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: 0x6E6E73))
            Spacer()
            Text(value)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color(hex: 0x1C1C1E))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var pairingTitle: String {
        switch status.phase {
        case .instructions: return "Scan the desktop QR"
        case .scanning: return "Ready to scan"
        case .pairing: return "Connecting…"
        case .paired: return "Paired!"
        case .expired: return "QR Code Expired"
        case .failed: return "Pairing failed"
        }
    }

    private var pairingTitleSize: CGFloat {
        switch status.phase {
        case .paired: return 28
        case .expired: return 26
        default: return 24
        }
    }

    private var pairingHeroIcon: String {
        switch status.phase {
        case .instructions, .scanning: return "qrcode.viewfinder"
        case .pairing: return "lock.shield"
        case .paired: return "checkmark"
        case .expired: return "clock.badge.xmark"
        case .failed: return "xmark"
        }
    }

    private var pairingHeroGradient: [Color] {
        switch status.phase {
        case .instructions, .scanning, .pairing:
            return [Color(hex: 0x007AFF), Color(hex: 0x0055D4)]
        case .paired:
            return [Color(hex: 0x30D158), Color(hex: 0x1A9E3D)]
        case .expired, .failed:
            return [Color(hex: 0xFF453A), Color(hex: 0xC02020)]
        }
    }

    private var pairingButtonTitle: String {
        switch status.phase {
        case .paired: return "Start Backup"
        case .expired: return "Scan Again"
        case .failed: return "Scan Again"
        default: return "Start Pairing"
        }
    }

    private var pairingButtonIcon: String {
        switch status.phase {
        case .paired: return "arrow.up.circle.fill"
        case .expired: return "qrcode.viewfinder"
        case .failed: return "qrcode.viewfinder"
        default: return "link"
        }
    }

    private var primaryAction: () -> Void {
        if status.phase == .expired || status.phase == .failed {
            return onScanAgain
        }
        return onStartPairing
    }

    private var isPrimaryActionDisabled: Bool {
        switch status.phase {
        case .pairing:
            return true
        case .paired, .expired, .failed:
            return false
        case .instructions, .scanning:
            return scannedQRCodeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
