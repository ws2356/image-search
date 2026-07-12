import SwiftUI

#if os(iOS)
struct TextFileCard: View {
    let state: MultiFileReceiveViewModel.FileDownloadState
    let shareAction: () -> Void
    @State private var showCopiedToast = false

    var body: some View {
        FileCardContainer(isDownloading: state.status == .downloading) {
            ExpandedFileCardLayout(state: state) {
                Text(state.inlineContent ?? "")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.foreground)
                    .lineLimit(5)
                    .frame(height: 120, alignment: .topLeading)
            } footer: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    CardActionButton(title: showCopiedToast ? "Copied!" : "Copy", icon: "doc.on.doc", style: .secondary) {
                        UIPasteboard.general.string = state.inlineContent ?? ""
                        withAnimation {
                            showCopiedToast = true
                        }
                    }

                    CardActionButton(title: "Share", icon: "square.and.arrow.up", style: .primary) {
                        shareAction()
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            ToastView(message: "Copied to clipboard", isShowing: $showCopiedToast)
        }
    }
}
#endif
