import SwiftUI

struct HomeView: View {
    let summary: HomeSummary
    let onPrimaryAction: () -> Void
    let onScanDesktop: () -> Void

    private let setupSteps = [
        SetupStep(
            id: "open-desktop",
            number: 1,
            title: "Open AuSearch on your PC",
            detail: "Open in your desktop browser. Then install and launch AuSearch.",
            link: "https://f.boldman.net/2"
        ),
        SetupStep(id: "add-mobile-folder", number: 2, title: "Add a Mobile Folder", detail: "Click Add Folder → Mobile Device in the PC app", link: nil),
        SetupStep(id: "scan-qr", number: 3, title: "Scan the QR code", detail: "A QR code appears on screen — scan it below to pair", link: nil),
    ]

    var body: some View {
        ScrollView {
            if hasSessionHistory {
                returningContent
            } else {
                firstTimeContent
            }
        }
        .compatibleScrollBounceBasedOnSize()
    }

    private var hasSessionHistory: Bool {
        summary.lastBackupDescription != nil || summary.previouslyTransferredDescription != nil
    }

    // MARK: - First-time user

    private var firstTimeContent: some View {
        VStack(spacing: 24) {
            heroSection
            setupSection

            Button(action: onPrimaryAction) {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                    Text("Scan QR Code")
                        .font(.system(size: 17, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color(hex: 0x007AFF))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

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

    // MARK: - Returning user

    private var returningContent: some View {
        VStack(spacing: 0) {
            Text(normalizedDesktopDisplayName(summary.desktopName) ?? "")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color(hex: 0x1C1C1E))
                .compatibleTracking(-0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 4)

            if summary.primaryAction != .scanDesktopQRCode {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: 0x30D158))
                        .frame(width: 9, height: 9)
                    Text("Connected")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x166534))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color(hex: 0xE6F9ED))
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 6)
            }

            VStack(spacing: 12) {
                if let warning = summary.interruptionWarning {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(hex: 0xFF9F0A))
                            .font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Backup was interrupted")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x1C1C1E))
                            Text(warning)
                                .font(.system(size: 13))
                                .foregroundStyle(Color(hex: 0x555555))
                                .lineSpacing(2)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xFFF3CD))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                statsCard

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
                        Text("Reconnect")
                            .font(.system(size: 17, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundStyle(Color(hex: 0x007AFF))
                            .background(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color(hex: 0xE5E5EA), lineWidth: 1.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "cable.connector")
                        .foregroundStyle(Color(hex: 0x3B5FC0))
                        .font(.system(size: 13))
                    Text("USB backups are usually up to 5× faster than Wi-Fi. Plug in anytime—AuBackup will switch to USB automatically.")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: 0x3B5FC0))
                        .lineSpacing(2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0xEEF2FF))
                .clipShape(RoundedRectangle(cornerRadius: 10))

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
            .padding(.top, 16)
        }
    }

    // MARK: - Components

    private var heroSection: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(
                        .linearGradient(
                            colors: [Color(hex: 0x0A84FF), Color(hex: 0x0040CC)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: Color(hex: 0x007AFF).opacity(0.45), radius: 12, y: 6)

                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.white)
            }

            Text("AuBackup")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color(hex: 0x1C1C1E))

            Text("Back up your photos & videos to your PC securely over Wi-Fi or USB or both")
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
            Text("Start on your PC first")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .textCase(.uppercase)
                .compatibleKerning(0.5)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                ForEach(Array(setupSteps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 12) {
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
                            setupStepDetail(step)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)

                    if index < setupSteps.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        }
    }

    private var statsCard: some View {
        VStack(spacing: 0) {
            if let lastBackup = summary.lastBackupDescription {
                statsRow(
                    iconColor: Color(hex: 0x007AFF),
                    iconBg: Color(hex: 0xE8F4FD),
                    iconName: "clock",
                    title: "Last backup",
                    subtitle: lastBackup
                )
                Divider().padding(.leading, 50)
            }

            if let pending = summary.pendingItemCount, pending > 0 {
                statsRow(
                    iconColor: Color(hex: 0x007AFF),
                    iconBg: Color(hex: 0xEEF4FF),
                    iconName: "photo.on.rectangle",
                    title: "\(pending) new items detected",
                    subtitle: nil,
                    titleBold: true
                )
                Divider().padding(.leading, 50)
            }

            if let transferred = summary.previouslyTransferredDescription {
                statsRow(
                    iconColor: Color(hex: 0x30D158),
                    iconBg: Color(hex: 0xE6F9ED),
                    iconName: "checkmark.circle",
                    title: "Previously transferred",
                    subtitle: transferred
                )
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }

    @ViewBuilder
    private func setupStepDetail(_ step: SetupStep) -> some View {
        if let link = step.link {
            (
                Text("Open ").foregroundColor(Color(hex: 0x6E6E73))
                + Text(link).foregroundColor(Color(hex: 0x007AFF))
                + Text(" in your desktop browser. Then install and launch AuSearch.").foregroundColor(Color(hex: 0x6E6E73))
            )
            .font(.system(size: 13))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(step.detail)
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statsRow(
        iconColor: Color,
        iconBg: Color,
        iconName: String,
        title: String,
        subtitle: String?,
        titleBold: Bool = false
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconBg)
                    .frame(width: 34, height: 34)
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: titleBold ? .semibold : .regular))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(hex: 0x6E6E73))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
    let link: String?
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
