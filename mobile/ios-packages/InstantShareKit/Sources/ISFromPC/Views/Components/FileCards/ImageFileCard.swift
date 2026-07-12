import SwiftUI

#if os(iOS)
struct ImageFileCard: View {
    let state: MultiFileReceiveViewModel.FileDownloadState
    let shareAction: () -> Void

    var body: some View {
        FileCardContainer(isDownloading: state.status == .downloading) {
            ExpandedFileCardLayout(state: state) {
                imagePreview
                    .frame(height: 160)
                    .clipped()
            } footer: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    CardActionButton(title: "Share", icon: "square.and.arrow.up", style: .primary) {
                        shareAction()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let fileURL = state.result?.imageFileURL,
           let uiImage = UIImage(contentsOfFile: fileURL.path) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        DesignSystem.Colors.secondaryText
            .opacity(0.1)
            .overlay(
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            )
    }
}

private extension QRClaimResult {
    var imageFileURL: URL? {
        switch self {
        case .image(let fileURL, _, _): return fileURL
        default: return nil
        }
    }
}
#endif
