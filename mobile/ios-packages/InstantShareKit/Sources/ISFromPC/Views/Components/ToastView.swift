import SwiftUI

#if os(iOS)
struct ToastView: View {
    let message: String
    @Binding var isShowing: Bool
    var duration: TimeInterval = 2

    var body: some View {
        Group {
            if isShowing {
                Text(message)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, DesignSystem.Spacing.xl)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(Capsule().fill(Color.black.opacity(0.8)))
                    .padding(.bottom, DesignSystem.Spacing.xl)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: isShowing) { _, newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                    withAnimation {
                        isShowing = false
                    }
                }
            }
        }
    }
}
#endif
