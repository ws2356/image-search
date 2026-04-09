import SwiftUI

struct PairingFlowView: View {
    let status: PairingStatus
    let onStartPairing: () -> Void
    let onShowExpired: () -> Void
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StatusCard(
                    title: pairingTitle,
                    subtitle: status.message,
                    systemImage: pairingIcon
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let desktopName = status.desktopName {
                            Label("Desktop: \(desktopName)", systemImage: "desktopcomputer")
                                .foregroundStyle(.secondary)
                        }

                        Label("Use a maintained QR scanning library such as CodeScanner when the live capture surface is implemented.", systemImage: "qrcode.viewfinder")
                            .foregroundStyle(.secondary)

                        Button(pairingButtonTitle, action: onStartPairing)
                            .buttonStyle(.borderedProminent)

                        Button("Preview Expired QR", action: onShowExpired)
                            .buttonStyle(.bordered)

                        Button("Back", action: onBack)
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var pairingTitle: String {
        switch status.phase {
        case .instructions:
            return "Scan the desktop QR"
        case .scanning:
            return "Ready to scan"
        case .pairing:
            return "Pairing in progress"
        case .paired:
            return "Pairing complete"
        case .expired:
            return "QR expired"
        }
    }

    private var pairingIcon: String {
        switch status.phase {
        case .instructions, .scanning:
            return "qrcode.viewfinder"
        case .pairing:
            return "lock.shield"
        case .paired:
            return "checkmark.shield.fill"
        case .expired:
            return "xmark.shield.fill"
        }
    }

    private var pairingButtonTitle: String {
        status.phase == .paired ? "Pair Again" : "Simulate Pairing Success"
    }
}

struct PermissionsGateView: View {
    let summary: PermissionSummary
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StatusCard(
                    title: "Backup preflight",
                    subtitle: "Request permissions only when they are about to be used, then start the transfer with the lightest possible flow.",
                    systemImage: "lock.shield.fill"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        PermissionRow(title: "Media Library", value: summary.mediaScope.title)
                        PermissionRow(
                            title: "Notifications",
                            value: summary.notificationsGranted ? "Granted" : "Requested when Start Backup is tapped"
                        )
                        PermissionRow(title: "Power", value: summary.isCharging ? "Charging" : "Running on battery")

                        if let excludedCategoryDescription = summary.excludedCategoryDescription {
                            Text(excludedCategoryDescription)
                                .foregroundStyle(.secondary)
                        }

                        if summary.lowBatteryWarningNeeded && !summary.isCharging {
                            Label("A low-battery dialog will appear immediately before transfer starts.", systemImage: "battery.25")
                                .foregroundStyle(.orange)
                        }

                        Button("Start Backup", action: onContinue)
                            .buttonStyle(.borderedProminent)

                        Button("Back", action: onBack)
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

struct TransferSessionView: View {
    let snapshot: TransferSnapshot
    let onStop: () -> Void
    let onSimulateCompletion: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StatusCard(
                    title: "Backup in progress",
                    subtitle: snapshot.statusMessage,
                    systemImage: "arrow.triangle.2.circlepath.circle.fill"
                ) {
                    VStack(alignment: .leading, spacing: 16) {
                        ProgressView(value: snapshot.progress) {
                            Text("\(snapshot.transferredCount) of \(snapshot.totalCount) items")
                        } currentValueLabel: {
                            Text(snapshot.etaDescription ?? "ETA unavailable")
                        }

                        HStack(spacing: 12) {
                            MetricPill(title: "Transferred", value: "\(snapshot.transferredCount)")
                            MetricPill(title: "Failed", value: "\(snapshot.failedCount)")
                            MetricPill(title: "Transport", value: snapshot.transport.title)
                        }

                        Label(snapshot.guidanceMessage, systemImage: snapshot.transport.systemImage)
                            .foregroundStyle(.secondary)

                        if snapshot.isIncompleteLibrary {
                            Label("Only the subset currently granted by iOS is being transferred.", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }

                        Button("Stop", role: .destructive, action: onStop)
                            .buttonStyle(.borderedProminent)

                        Button("Simulate Desktop Completion", action: onSimulateCompletion)
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

struct InterruptedSessionView: View {
    let reason: InterruptionReason
    let onResume: () -> Void
    let onReturnHome: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StatusCard(
                    title: reason.title,
                    subtitle: reason.message,
                    systemImage: reason.systemImage
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        Button("Resume Backup", action: onResume)
                            .buttonStyle(.borderedProminent)

                        Button("Return Home", action: onReturnHome)
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

struct CompletionStateView: View {
    let summary: CompletionSummary
    let onReturnHome: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StatusCard(
                    title: summary.title,
                    subtitle: summary.message,
                    systemImage: "checkmark.circle.fill"
                ) {
                    Button("Return Home", action: onReturnHome)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

struct StatusCard<Content: View>: View {
    let title: String
    let subtitle: String
    let systemImage: String
    @ViewBuilder let content: Content

    @ScaledMetric(relativeTo: .body) private var cardPadding = 20.0
    @ScaledMetric(relativeTo: .title3) private var iconSize = 22.0

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
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.tint)

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            Divider()

            content
        }
        .padding(cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
    }
}

struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct PermissionRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct BulletRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.caption2)
                .padding(.top, 6)
                .foregroundStyle(.tint)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
