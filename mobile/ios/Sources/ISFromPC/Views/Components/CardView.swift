import SwiftUI

struct CardView<Content: View>: View {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
            )
    }
}

#Preview {
    CardView {
        VStack(alignment: .leading, spacing: 8) {
            Text("Card Title").font(DesignSystem.Typography.h3)
            Text("Card content goes here").font(DesignSystem.Typography.body)
        }
    }
    .padding()
    .background(Color(.systemBackground))
}