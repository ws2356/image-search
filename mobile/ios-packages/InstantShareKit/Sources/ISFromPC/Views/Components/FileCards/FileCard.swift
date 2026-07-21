import SwiftUI

#if os(iOS)
struct FileCard: View {
    let state: MultiFileReceiveViewModel.FileDownloadState
    let shareAction: () -> Void

    var body: some View {
        switch state.entryType.lowercased() {
        case "text":
            TextFileCard(state: state, shareAction: shareAction)
        case "html":
            HTMLFileCard(state: state, shareAction: shareAction)
        case "link":
            WebLinkCard(state: state, shareAction: shareAction)
        case "file":
            let lowercasedContentType = state.contentType.lowercased()
            if lowercasedContentType.hasPrefix("text/") {
                TextFileCard(state: state, shareAction: shareAction)
            } else if lowercasedContentType.hasPrefix("image/") {
                ImageFileCard(state: state, shareAction: shareAction)
            } else {
                GenericFileCard(state: state, shareAction: shareAction)
            }
        default:
            GenericFileCard(state: state, shareAction: shareAction)
        }
    }
}
#endif
