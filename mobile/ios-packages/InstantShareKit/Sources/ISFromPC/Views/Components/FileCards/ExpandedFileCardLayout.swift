import SwiftUI

#if os(iOS)
struct ExpandedFileCardLayout<Body: View, Footer: View>: View {
    let state: MultiFileReceiveViewModel.FileDownloadState
    @ViewBuilder let bodyContent: () -> Body
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            header
            bodyContent()
                .frame(maxWidth: .infinity)
            footer()
        }
    }

    private var header: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            FileTypeBadge(entryType: state.entryType, filename: state.filename)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(state.filename.isEmpty ? "File \(state.index + 1)" : state.filename)
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(DesignSystem.Colors.foreground)
                    .lineLimit(1)

                Text(formatBytes(state.sizeBytes))
                    .font(DesignSystem.Typography.caption2)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }

            Spacer()
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }
}

#Preview {
    ExpandedFileCardLayout(
        state: MultiFileReceiveViewModel.FileDownloadState(
            index: 0,
            entryType: "text",
            filename: "notes.txt",
            contentType: "text/plain",
            sizeBytes: 1234,
            inlineContent: "Hello",
            status: .downloaded,
            result: .text("Hello")
        ),
        bodyContent: {
            Text("Preview body")
                .frame(height: 120, alignment: .topLeading)
        },
        footer: {
            Text("Footer")
        }
    )
    .padding()
    .background(Color.white)
}
#endif
