import SwiftUI

struct HomeView: View {
    let summary: HomeSummary
    let onPrimaryAction: () -> Void
    let onScanDesktop: () -> Void

    private let setupSteps = [
        SetupStep(id: "open-desktop", number: 1, title: "Open the desktop app", detail: "Install or launch Image Search on your computer."),
        SetupStep(id: "start-add-folder", number: 2, title: "Start Add Folder", detail: "Choose Mobile Device in the desktop flow."),
        SetupStep(id: "show-qr-page", number: 3, title: "Show the QR page", detail: "Keep the desktop pairing screen visible while you scan."),
        SetupStep(id: "backup-full-library", number: 4, title: "Back up the library", detail: "v1 supports the full eligible library, not album selection."),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                heroSection
                setupSection
                actionSection

                if summary.permissionScope.isIncomplete {
                    warningBanner(
                        icon: "exclamationmark.triangle.fill",
                        title: "Backup may be incomplete",
                        message: summary.permissionScope.detail,
                        tint: .orange
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var heroSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.linearGradient(
                    colors: [Color(hex: 0x007AFF), Color(hex: 0x0055D4)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 88, height: 88)
                .background(
                    Circle()
                        .fill(Color(hex: 0x007AFF).opacity(0.1))
                )

            Text("Album Transporter")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color(hex: 0x1C1C1E))

            Text("Back up your iPhone photos & videos to Image Search on desktop. Local only — no cloud, no account.")
                .font(.subheadline)
                .foregroundStyle(Color(hex: 0x6E6E73))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SETUP STEPS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .kerning(0.7)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                ForEach(Array(setupSteps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: 0x007AFF))
                                .frame(width: 28, height: 28)
                            Text("\(step.number)")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x1C1C1E))
                            Text(step.detail)
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: 0x6E6E73))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if index < setupSteps.count - 1 {
                        Divider()
                            .padding(.leading, 58)
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        }
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            if let desktopName = summary.desktopName {
                HStack(spacing: 8) {
                    Image(systemName: "desktopcomputer")
                        .foregroundStyle(Color(hex: 0x6E6E73))
                    Text(desktopName)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: 0x6E6E73))
                    Spacer()
                    if summary.primaryAction != .scanDesktopQRCode {
                        badgePill("Connected", color: Color(hex: 0x30D158))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
            }

            HStack(spacing: 10) {
                metricCard(title: "Pending", value: summary.pendingItemCount.map(String.init) ?? "—")

                if let lastBackupDescription = summary.lastBackupDescription {
                    metricCard(title: "Last backup", value: lastBackupDescription)
                }
            }

            Button(action: onPrimaryAction) {
                HStack(spacing: 8) {
                    Image(systemName: summary.primaryAction.systemImage)
                    Text(summary.primaryAction.title)
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color(hex: 0x007AFF))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            if summary.primaryAction.showsSecondaryScanAction {
                Button(action: onScanDesktop) {
                    HStack(spacing: 6) {
                        Image(systemName: "qrcode.viewfinder")
                        Text("Scan Desktop QR")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .foregroundStyle(Color(hex: 0x007AFF))
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: 0xE5E5EA), lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(hex: 0x6E6E73))
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0x1C1C1E))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    private func badgePill(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func warningBanner(icon: String, title: String, message: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.system(size: 16))
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x6E6E73))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xFFF3CD).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct SetupStep: Identifiable {
    let id: String
    let number: Int
    let title: String
    let detail: String
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
