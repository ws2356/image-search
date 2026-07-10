import SwiftUI

#if os(iOS)
struct CompactFileCardLayout<Trailing: View>: View {
    let state: MultiFileReceiveViewModel.FileDownloadState
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
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

            trailing()
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
    CompactFileCardLayout(
        state: MultiFileReceiveViewModel.FileDownloadState(
            index: 0,
            entryType: "file",
            filename: "design_assets.zip",
            contentType: "application/zip",
            sizeBytes: 24_700_000,
            inlineContent: nil,
            status: .downloaded,
            result: nil
        )
    ) {
        Text("Trailing")
    }
    .padding()
    .background(Color.white)
}
#endif
