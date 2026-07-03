import SwiftUI

#if os(iOS)
public struct LinkReceiveView: View {
    let urlString: String
    @State private var copied = false

    public init(urlString: String) {
        self.urlString = urlString
    }

    public var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            CardView {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "link")
                        .font(.system(size: 40))
                        .foregroundStyle(DesignSystem.Colors.primary)
                    Text("Web Link")
                        .font(DesignSystem.Typography.h3)
                    Text(urlString)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Colors.primary)
                        .textSelection(.enabled)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal)

            HStack(spacing: DesignSystem.Spacing.md) {
                PrimaryButton(title: "Copy Link", icon: "doc.on.doc", style: .secondary) {
                    copyToClipboard()
                }

                if let url = URL(string: urlString) {
                    Link(destination: url) {
                        PrimaryButton(title: "Open", icon: "safari", style: .primary) {}
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = urlString
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copied = false
        }
    }
}
#endif
