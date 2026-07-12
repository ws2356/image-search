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
                    CardActionButton(title: "Copy Link", icon: "doc.on.doc", style: .secondary) {
                        copyToClipboard(urlString)
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
            if showCopiedToast {
                toast("Copied to clipboard")
            }
        }
    }

    private func copyToClipboard(_ urlString: String) {
        UIPasteboard.general.string = urlString
        withAnimation {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showCopiedToast = false
            }
        }
    }

    private func toast(_ message: String) -> some View {
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
#endif
