import SwiftUI

#if os(iOS)
struct CardActionButton: View {
    let title: String
    var icon: String? = nil
    let style: ButtonStyle
    let action: () -> Void

    enum ButtonStyle {
        case primary
        case secondary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .medium))
                }
                Text(title)
                    .font(DesignSystem.Typography.captionMedium)
            }
            .frame(minWidth: 80)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return DesignSystem.Colors.primary
        case .secondary: return DesignSystem.Colors.foreground
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return DesignSystem.Colors.primary.opacity(0.1)
        case .secondary: return DesignSystem.Colors.cardBackground.opacity(0.8)
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        CardActionButton(title: "Copy", icon: "doc.on.doc", style: .secondary) {}
        CardActionButton(title: "Share", icon: "square.and.arrow.up", style: .primary) {}
    }
    .padding()
    .background(Color.white)
}
#endif
