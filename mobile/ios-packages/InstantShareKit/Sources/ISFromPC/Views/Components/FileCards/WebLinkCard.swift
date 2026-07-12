import SwiftUI

#if os(iOS)
struct WebLinkCard: View {
    let state: MultiFileReceiveViewModel.FileDownloadState
    let shareAction: () -> Void
    @State private var showCopiedToast = false

    var body: some View {
        let urlString = state.downloadedTextContent ?? state.inlineContent ?? ""
        FileCardContainer(isDownloading: state.status == .downloading) {
            ExpandedFileCardLayout(state: state) {
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "link")
                        .font(.system(size: 32))
                        .foregroundStyle(DesignSystem.Colors.primary)

                    Text(urlString)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: 120)
            } footer: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    CardActionButton(title: showCopiedToast ? "Copied!" : "Copy Link", icon: "doc.on.doc", style: .secondary) {
                        UIPasteboard.general.string = urlString
                        withAnimation {
                            showCopiedToast = true
                        }
                    }

                    if let url = URL(string: urlString) {
                        CardActionButton(title: "Open", icon: "safari", style: .secondary) {
                            UIApplication.shared.open(url)
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
