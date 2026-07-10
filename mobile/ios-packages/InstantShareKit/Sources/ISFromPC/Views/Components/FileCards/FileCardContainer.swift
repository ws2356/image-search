import SwiftUI

#if os(iOS)
struct FileCardContainer<Content: View>: View {
    let isDownloading: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        FileCardBackground {
            content()
        }
        .overlay(
            Group {
                if isDownloading {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.card)
                        .fill(DesignSystem.Colors.foreground.opacity(0.08))
                        .overlay(
                            ProgressView()
                                .controlSize(.regular)
                                .tint(DesignSystem.Colors.primary)
                        )
                }
            }
        )
        .disabled(isDownloading)
    }
}

#Preview {
    VStack(spacing: 16) {
        FileCardContainer(isDownloading: false) {
            Text("Idle card")
        }
        FileCardContainer(isDownloading: true) {
            Text("Downloading card")
        }
    }
    .padding()
    .background(Color.white)
}
#endif
