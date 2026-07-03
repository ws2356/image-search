import SwiftUI

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    let style: ButtonStyle
    var isLoading: Bool = false
    let action: () -> Void

    enum ButtonStyle {
        case primary
        case secondary
        case destructive
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if let icon {
                    Image(systemName: icon)
                }
                Text(title)
                    .font(DesignSystem.Typography.h4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.button))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var foregroundColor: Color {
        switch style {
        case .primary: return .white
        case .secondary: return DesignSystem.Colors.primary
        case .destructive: return DesignSystem.Colors.error
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary: return DesignSystem.Colors.primary
        case .secondary: return .clear
        case .destructive: return DesignSystem.Colors.error.opacity(0.12)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        PrimaryButton(title: "Primary", style: .primary) {}
        PrimaryButton(title: "Secondary", style: .secondary) {}
        PrimaryButton(title: "Destructive", style: .destructive) {}
        PrimaryButton(title: "Loading", style: .primary, isLoading: true) {}
    }
    .padding()
    .background(Color(.systemBackground))
}