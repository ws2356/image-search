import SwiftUI

#if os(iOS)
struct LoadingSpinner: View {
    var message: String = "Connecting..."

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(DesignSystem.Colors.primary)
            Text(message)
                .font(DesignSystem.Typography.h3)
                .foregroundStyle(DesignSystem.Colors.foreground)
            Spacer()
        }
    }
}

struct TransferProgress: View {
    let progress: Double

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            ProgressView(value: progress)
                .tint(DesignSystem.Colors.primary)
            Text("\(Int(progress * 100))%")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
    }
}

struct ScanningBadge: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Circle()
                .fill(DesignSystem.Colors.primary)
                .frame(width: 8, height: 8)
                .opacity(isAnimating ? 0.4 : 1.0)
                .animation(
                    .easeInOut(duration: 1.0).repeatForever(autoreverses: true),
                    value: isAnimating
                )
            Text("Scanning...")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
        .onAppear { isAnimating = true }
    }
}

#Preview {
    VStack(spacing: 24) {
        LoadingSpinner()
        TransferProgress(progress: 0.65)
        ScanningBadge()
    }
    .background(Color(.systemBackground))
}
#endif