import SwiftUI
import UIKit

struct QRTransferResultView: View {
    let result: QRClaimResult
    @StateObject var viewModel: ISQRResultViewModel

    @State private var showShareSheet = false

    init(result: QRClaimResult, delegate: ISQRDeliverDelegate) {
        self.result = result
        self._viewModel = StateObject(wrappedValue: ISQRResultViewModel(delegate: delegate))
    }

    var body: some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { viewModel.onComplete() }
                        .font(DesignSystem.Typography.h4)
                        .foregroundStyle(DesignSystem.Colors.primary)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: result.asShareItems)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch result {
        case .text(let text):
            htmlContentView(html: Self.htmlWrapping(text))
        case .html(let html):
            htmlContentView(html: html)
        case .link(let urlString):
            LinkReceiveView(urlString: urlString)
        default:
            EmptyView()
        }
    }

    private func htmlContentView(html: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            CardView {
                RichTextReceiveView(html: html)
            }
            .padding(.horizontal)

            PrimaryButton(title: "Share", icon: "square.and.arrow.up", style: .secondary) {
                shareCurrentContent()
            }
            .padding(.horizontal)
        }
    }

    private static func htmlWrapping(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
        <html><body style="font-family: -apple-system, monospace; \
        font-size: 14px; white-space: pre-wrap; word-wrap: break-word; \
        padding: 16px; margin: 0;">\(escaped)</body></html>
        """
    }

    private func shareCurrentContent() {
        showShareSheet = true
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension QRClaimResult {
    var asShareItems: [Any] {
        var items: [Any] = []
        switch self {
        case .text(let text):
            items = [text]
        case .html(let html):
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).html")
            try? html.data(using: .utf8)?.write(to: tempURL)
            items = [tempURL]
        case .link(let urlString):
            if let url = URL(string: urlString) {
                items = [url]
            } else {
                items = [urlString]
            }
        case .image(let fileURL, _, _):
            items = [Self.sanitizedFileURL(fileURL)]
        case .file(let fileURL, _, _):
            items = [Self.sanitizedFileURL(fileURL)]
        case .multiFile:
            items = []
        }
        return items
    }

    static private func sanitizedFileURL(_ url: URL) -> URL {
        let filename = url.lastPathComponent
        let sanitized = filename.drop(while: { $0 == "." })
        guard sanitized.isEmpty == false, sanitized.count != filename.count else { return url }
        let newURL = url.deletingLastPathComponent().appendingPathComponent(String(sanitized))
        try? FileManager.default.moveItem(at: url, to: newURL)
        return newURL
    }
}
