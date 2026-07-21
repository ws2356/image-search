//
//  UserInstructionView.swift
//  SnapGet
//
//  First-time user instruction screen explaining PC↔mobile sharing setup.
//

import SwiftUI

#if os(iOS)
public struct UserInstructionView: View {
    @State private var showCopiedToast = false
    
    public init() {}

    private let downloadURL = "https://www.boldman.net/snapget.html#download"

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                headerSection
                usageCardsSection
                pcSetupSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            if let iconImage = UIImage(named: "ic_app") {
                Image(uiImage: iconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: Color.black.opacity(0.15), radius: 12, y: 6)
            }

            Text("SnapGet")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Color(hex: 0x1C1C1E))

            Text("Instantly share files, images, text and links between your phone and PC")
                .font(.subheadline)
                .foregroundStyle(Color(hex: 0x6E6E73))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: - Usage Cards

    private var usageCardsSection: some View {
        VStack(spacing: 12) {
            UsageCard(
                iconName: "desktopcomputer",
                iconColor: Color(hex: 0x007AFF),
                iconBackground: Color(hex: 0xE8F4FD),
                title: "PC to Mobile",
                description: "Right-click any file, image, text or link on your PC and share them using the SnapGet desktop app."
            )

            UsageCard(
                iconName: "iphone",
                iconColor: Color(hex: 0x34C759),
                iconBackground: Color(hex: 0xE8FDE8),
                title: "Mobile to PC",
                description: "Select files, photos, or text on your phone and share them to your PC. Requires the SnapGet desktop app."
            )
        }
    }

    // MARK: - PC Setup Section

    private var pcSetupSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PC Setup")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0x6E6E73))
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                SetupStepRow(
                    number: 1,
                    title: "Download SnapGet for PC",
                    detail: Text(downloadURL),
                    isLink: true,
                    onTap: copyDownloadURL
                )
                .overlay(alignment: .bottom) {
                    Divider().padding(.leading, 56)
                }

                SetupStepRow(
                    number: 2,
                    title: "Install SnapGet on your PC",
                    detail: Text("Run the installer and open the app."),
                    isLink: false
                )
                .overlay(alignment: .bottom) {
                    Divider().padding(.leading, 56)
                }

                SetupStepRow(
                    number: 3,
                    title: "Enable the share extension",
                    detail: Text("For macOS, visit ") + Text("System Settings > General > Login Items & Extensions > Extensions > Sharing").bold() + Text(", turn on SnapGet."),
                    isLink: false
                )
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        }
        .overlay(alignment: .center) {
            if showCopiedToast {
                toastView
                    .padding(.bottom, -40)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var toastView: some View {
        Text("Link copied to clipboard")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(hex: 0x1C1C1E))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func copyDownloadURL() {
        UIPasteboard.general.string = downloadURL
        withAnimation {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedToast = false
            }
        }
    }
}

// MARK: - Subviews

private struct UsageCard: View {
    let iconName: String
    let iconColor: Color
    let iconBackground: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 40, height: 40)
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x1C1C1E))
                Text(description)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(hex: 0x6E6E73))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    }
}

private struct SetupStepRow: View {
    let number: Int
    let title: String
    let detail: Text
    let isLink: Bool
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: 0x007AFF))
                        .frame(width: 28, height: 28)
                    Text("\(number)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(hex: 0x1C1C1E))
                    if isLink {
                        detail
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: 0x007AFF))
                    } else {
                        detail
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: 0x6E6E73))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Color Hex Extension

private extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
#endif
