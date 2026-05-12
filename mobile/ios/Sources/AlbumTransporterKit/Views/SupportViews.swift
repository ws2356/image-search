import SwiftUI

func heroCircle(icon: String, gradient: [Color], size: CGFloat = 100) -> some View {
    ZStack {
        Circle()
            .fill(.linearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .shadow(color: gradient.first?.opacity(0.4) ?? .clear, radius: 16, y: 8)

        Image(systemName: icon)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
    }
}

struct ActionButton: View {
    let title: String
    var icon: String? = nil
    let style: ActionButtonStyle
    var height: CGFloat? = nil
    let action: () -> Void

    enum ActionButtonStyle {
        case primary, secondary, cancelSecondary, destructive, plain
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
            .frame(height: height ?? defaultHeight)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: style == .plain ? 8 : 14))
            .overlay(borderOverlay)
        }
        .buttonStyle(.plain)
    }

    private var defaultHeight: CGFloat {
        style == .plain ? 36 : 52
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return Color(hex: 0x007AFF)
        case .cancelSecondary: return Color(hex: 0xFF453A)
        case .destructive: return Color(hex: 0xFF453A)
        case .plain: return Color(hex: 0x007AFF)
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return Color(hex: 0x007AFF)
        case .secondary: return Color.white
        case .cancelSecondary: return Color.white
        case .destructive: return Color(hex: 0xFFF1F0)
        case .plain: return .clear
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if style == .secondary || style == .cancelSecondary {
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

extension View {
    @ViewBuilder
    func compatibleScrollBounceBasedOnSize() -> some View {
        if #available(iOS 16.4, *) {
            self.scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleKerning(_ value: CGFloat) -> some View {
        if #available(iOS 16.0, *) {
            self.kerning(value)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleTracking(_ value: CGFloat) -> some View {
        if #available(iOS 16.0, *) {
            self.tracking(value)
        } else {
            self
        }
    }

    @ViewBuilder
    func compatibleOnChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
        if #available(iOS 17.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value, perform: action)
        }
    }
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
