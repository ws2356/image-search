import SwiftUI

struct HomeView: View {
    let summary: HomeSummary
    let onPrimaryAction: () -> Void
    let onScanDesktop: () -> Void

    private let setupSteps = [
        SetupStep(id: "open-desktop", title: "Open the desktop app.", detail: "Install or launch Image Search on your computer."),
        SetupStep(id: "start-add-folder", title: "Start Add Folder.", detail: "Choose Mobile Device in the desktop flow."),
        SetupStep(id: "show-qr-page", title: "Show the QR page.", detail: "Keep the desktop pairing screen visible while you scan."),
        SetupStep(id: "backup-full-library", title: "Back up the full library.", detail: "v1 supports the full eligible library, not album selection."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StatusCard(
                    title: "What this app does",
                    subtitle: "A simple local-only companion flow for moving the eligible iPhone library into Image Search on desktop.",
                    systemImage: "info.circle.fill"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        BulletRow(text: "v1 backs up the full eligible local library only. It does not do album selection or cloud sync.")
                        BulletRow(text: "No account or cloud relay is required. Pairing and transfer stay between the phone and the desktop app.")
                        BulletRow(text: "Notification permission is requested only when Start Backup is tapped, because interruption and completion alerts may happen later in a long session.")
                        BulletRow(text: "Operational telemetry is sent through OpenTelemetry and must stay content-safe.")
                    }
                }

                StatusCard(
                    title: "PC-first setup",
                    subtitle: "The desktop app creates the mobile folder and remains the session authority.",
                    systemImage: "desktopcomputer.and.iphone"
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(setupSteps) { step in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.title)
                                        .font(.headline)
                                    Text(step.detail)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                StatusCard(
                    title: summary.primaryAction.title,
                    subtitle: summary.detailMessage,
                    systemImage: summary.primaryAction.systemImage
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let desktopName = summary.desktopName {
                            Label("Last desktop: \(desktopName)", systemImage: "desktopcomputer")
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 12) {
                            MetricPill(title: "Pending", value: summary.pendingItemCount.map(String.init) ?? "Unknown")

                            if let lastBackupDescription = summary.lastBackupDescription {
                                MetricPill(title: "Last backup", value: lastBackupDescription)
                            }
                        }

                        Button(summary.primaryAction.title, action: onPrimaryAction)
                            .buttonStyle(.borderedProminent)

                        if summary.primaryAction.showsSecondaryScanAction {
                            Button("Scan Desktop QR", action: onScanDesktop)
                                .buttonStyle(.bordered)
                        }
                    }
                }

                if summary.permissionScope.isIncomplete {
                    StatusCard(
                        title: "Backup may be incomplete",
                        subtitle: summary.permissionScope.detail,
                        systemImage: "exclamationmark.triangle.fill"
                    ) {
                        Text("If permission scope changes later, the pending count and backup scope should refresh instead of preserving stale numbers.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct SetupStep: Identifiable {
    let id: String
    let title: String
    let detail: String
}
