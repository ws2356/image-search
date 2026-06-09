import SwiftUI
import Common

// MARK: - Shared Components


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
