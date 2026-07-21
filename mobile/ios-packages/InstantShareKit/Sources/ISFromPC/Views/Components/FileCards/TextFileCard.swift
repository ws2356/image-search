import SwiftUI

#if os(iOS)
struct TextFileCard: View {
    let state: MultiFileReceiveViewModel.FileDownloadState
    let shareAction: () -> Void
    @State private var showCopiedToast = false

    var body: some View {
        FileCardContainer(isDownloading: state.status == .downloading) {
            ExpandedFileCardLayout(state: state) {
                if let preview = state.textPreviewContent {
                    Text(preview)
                        .font(DesignSystem.Typography.monoBody)
                        .foregroundStyle(DesignSystem.Colors.foreground)
                        .lineLimit(5)
                        .truncationMode(.tail)
                        .frame(height: 120, alignment: .topLeading)
                } else {
                    placeholder
                }
            } footer: {
                HStack(spacing: DesignSystem.Spacing.md) {
                    CardActionButton(title: "Copy", icon: "doc.on.doc", style: .secondary) {
                        UIPasteboard.general.string = state.textPreviewContent ?? ""
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

    private var placeholder: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(DesignSystem.Colors.secondaryText)

            Text(state.status == .failed ? "Failed to load preview" : "Preview not available")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: 120)
    }
}

#Preview {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("preview-sample.txt")
    try? "This text was read from a downloaded file.".write(to: fileURL, atomically: true, encoding: .utf8)

    return VStack(spacing: DesignSystem.Spacing.lg) {
        TextFileCard(
            state: MultiFileReceiveViewModel.FileDownloadState(
                index: 0,
                entryType: "text",
                filename: "notes.txt",
                contentType: "text/plain",
                sizeBytes: 1234,
                inlineContent: "This is inline text content that should appear in the preview area.",
                status: .downloaded,
                result: .text("This is inline text content that should appear in the preview area.")
            )
        ) {}

        TextFileCard(
            state: MultiFileReceiveViewModel.FileDownloadState(
                index: 1,
                entryType: "file",
                filename: "data.json",
                contentType: "text/plain",
                sizeBytes: 5678,
                inlineContent: nil,
                status: .downloaded,
                result: .file(fileURL: fileURL, contentType: "text/plain", filename: "data.json")
            )
        ) {}

        TextFileCard(
            state: MultiFileReceiveViewModel.FileDownloadState(
                index: 2,
                entryType: "file",
                filename: "missing.txt",
                contentType: "text/plain",
                sizeBytes: 100,
                inlineContent: nil,
                status: .failed,
                result: nil,
                errorMessage: "Download failed"
            )
        ) {}
    }
    .padding()
    .background(Color.white)
}
#endif
