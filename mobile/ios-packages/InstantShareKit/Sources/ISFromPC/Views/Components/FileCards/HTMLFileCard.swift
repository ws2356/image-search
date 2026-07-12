import SwiftUI

#if os(iOS)
struct HTMLFileCard: View {
    let state: MultiFileReceiveViewModel.FileDownloadState
    let shareAction: () -> Void
    @State private var showCopiedToast = false

    var body: some View {
        let html = state.downloadedTextContent ?? state.inlineContent ?? ""
        FileCardContainer(isDownloading: state.status == .downloading) {
            ExpandedFileCardLayout(state: state) {
                RichTextWebView(html: html)
                    .frame(height: 120)
            } footer: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    CardActionButton(title: showCopiedToast ? "Copied!" : "Copy", icon: "doc.on.doc", style: .secondary) {
                        guard let data = html.data(using: .utf8) else { return }
                        UIPasteboard.general.setData(data, forPasteboardType: "public.html")
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
