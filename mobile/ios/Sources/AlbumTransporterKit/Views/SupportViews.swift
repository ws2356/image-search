import SwiftUI

// MARK: - Pairing Flow

struct PairingFlowView: View {
    let status: PairingStatus
    @Binding var scannedQRCodeValue: String
    let onStartPairing: () -> Void
    let onShowExpired: () -> Void
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                pairingHero

                if status.phase == .paired {
                    destinationCard
                }

#if os(iOS)
                if status.phase == .instructions || status.phase == .scanning {
                    LiveQRCodeScannerCard(
                        status: status,
                        scannedQRCodeValue: $scannedQRCodeValue,
                        onStartPairing: onStartPairing
                    )
                }
#endif

                pasteSection

                VStack(spacing: 10) {
                    ActionButton(
                        title: pairingButtonTitle,
                        icon: pairingButtonIcon,
                        style: .primary,
                        action: onStartPairing
                    )
                    .disabled(isPairingActionDisabled)

                    if status.phase != .paired {
                        ActionButton(
                            title: "Preview Expired QR",
                            icon: "clock.badge.xmark",
                            style: .secondary,
                            action: onShowExpired
                        )
                    }

                    ActionButton(title: "Back", icon: "chevron.left", style: .plain, action: onBack)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private var pairingHero: some View {
        VStack(spacing: 12) {
            ZStack {
                if status.phase == .pairing {
                    ForEach(0..<3, id: \.self) { ring in
                        Circle()
                            .stroke(Color(hex: 0x007AFF).opacity(0.15 + Double(ring) * 0.05), lineWidth: 2)
                            .frame(width: 100 + CGFloat(ring) * 24, height: 100 + CGFloat(ring) * 24)
                    }
                }

                heroCircle(
                    icon: pairingHeroIcon,
                    gradient: pairingHeroGradient
                )
            }

            Text(pairingTitle)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color(hex: 0x1C1C1E))

            Text(status.message)
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var destinationCard: some View {
        VStack(spacing: 0) {
            if let desktopName = status.desktopName {
                infoRow(icon: "desktopcomputer", label: "Desktop", value: desktopName)
                Divider().padding(.leading, 42)
            }
            if let sessionID = status.sessionID {
                infoRow(icon: "number", label: "Session", value: sessionID)
                Divider().padding(.leading, 42)
            }
            if let transport = status.transport {
                infoRow(icon: transport.systemImage, label: "Transport", value: transport.title)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
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

    private var pasteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Or paste the pairing link:", systemImage: "doc.on.clipboard")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: 0x6E6E73))

            TextField("Paste the desktop pairing link", text: $scannedQRCodeValue, axis: .vertical)
                .lineLimit(2...4)
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(hex: 0xE5E5EA), lineWidth: 1)
                )
#if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
#endif

            PasteButton(payloadType: String.self) { strings in
                if let firstValue = strings.first {
                    scannedQRCodeValue = firstValue
                }
            }
            .buttonStyle(.bordered)
            .tint(Color(hex: 0x007AFF))
        }
        .padding(16)
        .background(Color(hex: 0xF2F2F7))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var pairingTitle: String {
        switch status.phase {
        case .instructions: return "Scan the desktop QR"
        case .scanning: return "Ready to scan"
        case .pairing: return "Pairing…"
        case .paired: return "Paired successfully"
        case .expired: return "QR expired"
        case .failed: return "Pairing failed"
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
        case .expired:
            return [Color(hex: 0xFF9F0A), Color(hex: 0xE07800)]
        case .failed:
            return [Color(hex: 0xFF453A), Color(hex: 0xC02020)]
        }
    }

    private var pairingButtonTitle: String {
        status.phase == .paired ? "Pair Again" : "Start Pairing"
    }

    private var pairingButtonIcon: String {
        status.phase == .paired ? "arrow.clockwise" : "link"
    }

    private var isPairingActionDisabled: Bool {
        status.phase == .pairing || scannedQRCodeValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Permissions Gate

struct PermissionsGateView: View {
    let summary: PermissionSummary
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    heroCircle(icon: "lock.shield.fill", gradient: [Color(hex: 0x007AFF), Color(hex: 0x0055D4)])

                    Text("Backup preflight")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(hex: 0x1C1C1E))

                    Text("Checking permissions before starting.")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: 0x6E6E73))
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 0) {
                    PermissionRow(title: "Media Library", value: summary.mediaScope.title,
                                  icon: "photo.on.rectangle", isGranted: summary.mediaScope == .full)
                    Divider().padding(.leading, 42)
                    PermissionRow(title: "Notifications", value: summary.notificationsGranted ? "Granted" : "Will request",
                                  icon: "bell.badge", isGranted: summary.notificationsGranted)
                    Divider().padding(.leading, 42)
                    PermissionRow(title: "Power", value: summary.isCharging ? "Charging" : "On battery",
                                  icon: "battery.100.bolt", isGranted: summary.isCharging)
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.06), radius: 3, y: 1)

                if let excludedCategoryDescription = summary.excludedCategoryDescription {
                    infoBanner(message: excludedCategoryDescription, tint: Color(hex: 0x007AFF))
                }

                if summary.lowBatteryWarningNeeded && !summary.isCharging {
                    warningBanner(message: "Low battery — a dialog will appear before transfer starts.", tint: .orange)
                }

                VStack(spacing: 10) {
                    ActionButton(title: "Start Backup", icon: "arrow.up.circle.fill", style: .primary, action: onContinue)
                    ActionButton(title: "Back", icon: "chevron.left", style: .secondary, action: onBack)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func infoBanner(message: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xE8F4FD))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func warningBanner(message: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "battery.25")
                .foregroundStyle(tint)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xFFF3CD).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Transfer Session

struct TransferSessionView: View {
    let snapshot: TransferSnapshot
    let onStop: () -> Void
    let onSimulateCompletion: () -> Void

    private var progressPercent: Int {
        Int(snapshot.progress * 100)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                transportBadge

                donutProgress

                statsGrid

                if let eta = snapshot.etaDescription {
                    Text(eta)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x1C1C1E))
                        .frame(maxWidth: .infinity)
                }

                guidanceHint

                if snapshot.isIncompleteLibrary {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Only the subset currently granted by iOS is being transferred.")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: 0x6E6E73))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xFFF3CD).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                VStack(spacing: 10) {
                    Button(action: onStop) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                            Text("Stop Backup")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .foregroundStyle(Color(hex: 0xFF453A))
                        .background(Color(hex: 0xFFF1F0))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    ActionButton(
                        title: "Finish Backup",
                        icon: "checkmark.circle",
                        style: .secondary,
                        action: onSimulateCompletion
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var transportBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: snapshot.transport.systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(snapshot.transport.title)
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .foregroundStyle(transportColor)
        .background(transportBackground)
        .clipShape(Capsule())
    }

    private var donutProgress: some View {
        ZStack {
            Circle()
                .stroke(Color(hex: 0xE5E5EA), lineWidth: 12)

            Circle()
                .trim(from: 0, to: snapshot.progress)
                .stroke(
                    transportColor,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 4) {
                Text("\(progressPercent)%")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                Text("\(snapshot.transferredCount) of \(snapshot.totalCount)")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x6E6E73))
            }
        }
        .frame(width: 180, height: 180)
        .padding(.vertical, 8)
    }

    private var statsGrid: some View {
        HStack(spacing: 0) {
            statColumn(label: "Transferred", value: "\(snapshot.transferredCount)", color: Color(hex: 0x30D158))
            Divider().frame(height: 40)
            statColumn(label: "Failed", value: "\(snapshot.failedCount)", color: Color(hex: 0xFF453A))
            Divider().frame(height: 40)
            statColumn(label: "Transport", value: snapshot.transport.title, color: transportColor)
        }
        .padding(.vertical, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }

    private func statColumn(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: 0x6E6E73))
        }
        .frame(maxWidth: .infinity)
    }

    private var guidanceHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: snapshot.transport == .usb ? "checkmark.circle.fill" : "bolt.horizontal.fill")
                .foregroundStyle(snapshot.transport == .usb ? Color(hex: 0x30D158) : Color(hex: 0x3B5FC0))
            Text(snapshot.guidanceMessage)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(snapshot.transport == .usb ? Color(hex: 0xE6F9ED) : Color(hex: 0xEEF2FF))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var transportColor: Color {
        snapshot.transport == .usb ? Color(hex: 0x30D158) : Color(hex: 0x007AFF)
    }

    private var transportBackground: Color {
        snapshot.transport == .usb ? Color(hex: 0xE6F9ED) : Color(hex: 0xE8F4FD)
    }
}

// MARK: - Interrupted Session

struct InterruptedSessionView: View {
    let reason: InterruptionReason
    let onResume: () -> Void
    let onReturnHome: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    heroCircle(icon: reason.systemImage, gradient: interruptionGradient)

                    Text(reason.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color(hex: 0x1C1C1E))

                    Text(reason.message)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: 0x6E6E73))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)

                if reason == .wifiLost {
                    troubleshootingSection
                }

                VStack(spacing: 10) {
                    ActionButton(title: "Resume Backup", icon: "arrow.clockwise", style: .primary, action: onResume)
                    ActionButton(title: "Return Home", icon: "house", style: .secondary, action: onReturnHome)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var troubleshootingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Troubleshooting")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x7D0E00))

            VStack(alignment: .leading, spacing: 8) {
                tipRow("Make sure both devices are on the same Wi-Fi network.")
                tipRow("Check that the desktop app is still running.")
                tipRow("Try connecting via USB cable for a more stable transfer.")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xFDECEA))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(Color(hex: 0x7D0E00))
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x7D0E00))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var interruptionGradient: [Color] {
        switch reason {
        case .stoppedByUser, .pausedBySystem:
            return [Color(hex: 0xFF9F0A), Color(hex: 0xE07800)]
        case .wifiLost:
            return [Color(hex: 0xFF453A), Color(hex: 0xC02020)]
        case .desktopUnreachable, .reconnectRequired:
            return [Color(hex: 0x636366), Color(hex: 0x3A3A3C)]
        }
    }
}

// MARK: - Completion

struct CompletionStateView: View {
    let summary: CompletionSummary
    let onReturnHome: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 14) {
                    heroCircle(
                        icon: "checkmark",
                        gradient: [Color(hex: 0x34C759), Color(hex: 0x2A9D47)]
                    )

                    Text(summary.title)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(Color(hex: 0x1C1C1E))

                    Text(summary.message)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: 0x6E6E73))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)

                ActionButton(title: "Done", icon: "house", style: .primary, action: onReturnHome)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

// MARK: - Shared Components

private func heroCircle(icon: String, gradient: [Color]) -> some View {
    ZStack {
        Circle()
            .fill(.linearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 80, height: 80)
            .shadow(color: gradient.first?.opacity(0.4) ?? .clear, radius: 16, y: 8)

        Image(systemName: icon)
            .font(.system(size: 32, weight: .semibold))
            .foregroundStyle(.white)
    }
}

struct ActionButton: View {
    let title: String
    var icon: String? = nil
    let style: ActionButtonStyle
    let action: () -> Void

    enum ActionButtonStyle {
        case primary, secondary, destructive, plain
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .font(.system(size: style == .plain ? 15 : 17, weight: style == .plain ? .medium : .semibold))
            }
            .frame(maxWidth: style == .plain ? nil : .infinity)
            .frame(height: style == .plain ? 36 : 52)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: style == .plain ? 8 : 14))
            .overlay(borderOverlay)
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return Color(hex: 0x007AFF)
        case .destructive: return Color(hex: 0xFF453A)
        case .plain: return Color(hex: 0x007AFF)
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return Color(hex: 0x007AFF)
        case .secondary: return Color.white
        case .destructive: return Color(hex: 0xFFF1F0)
        case .plain: return .clear
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if style == .secondary {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: 0xE5E5EA), lineWidth: 1.5)
        }
    }
}

struct StatusCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x007AFF))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x1C1C1E))
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: 0x6E6E73))
                }
            }

            Divider()

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}

struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: 0x6E6E73))
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: 0x1C1C1E))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(hex: 0xF2F2F7))
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct PermissionRow: View {
    let title: String
    let value: String
    var icon: String = "circle"
    var isGranted: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(isGranted ? Color(hex: 0x30D158) : Color(hex: 0xFF9F0A))
                .frame(width: 20)
            Text(title)
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: 0x1C1C1E))
            Spacer()
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: 0x6E6E73))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

struct BulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(hex: 0x007AFF))
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: 0x6E6E73))
        }
        .accessibilityElement(children: .combine)
    }
}
