import SwiftUI

#if os(iOS)
struct GenericFileCard: View {
    let state: MultiFileReceiveViewModel.FileDownloadState
    let shareAction: () -> Void

    var body: some View {
        FileCardContainer(isDownloading: state.status == .downloading) {
            CompactFileCardLayout(state: state) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    CardActionButton(title: "Share", icon: "square.and.arrow.up", style: .primary) {
                        shareAction()
                    }
                }
            }
        }
        .frame(height: 72)
    }
}
#endif
