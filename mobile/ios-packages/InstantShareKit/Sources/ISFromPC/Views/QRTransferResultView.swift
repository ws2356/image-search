import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(iOS)
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
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(items: result.asShareItems)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch result {
        case .text(let text):
            textReceiveView(text: text, isHTML: false)
        case .html(let html):
            textReceiveView(text: html, isHTML: true)
        case .link(let urlString):
            LinkReceiveView(urlString: urlString)
        default:
            EmptyView()
        }
    }

    private func textReceiveView(text: String, isHTML: Bool) -> some View {
        VStack(spacing: 0) {
            // Header bar matching design spec
            headerBar
            
            Divider()
            
            // Scrollable content
            ScrollView {
                Group {
                    if isHTML {
                        htmlContent(text)
                    } else {
                        Text(text)
                            .font(DesignSystem.Typography.monoBody)
                            .foregroundStyle(DesignSystem.Colors.foreground)
                    }
                }
                .padding(DesignSystem.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignSystem.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xl))
                .padding(DesignSystem.Spacing.lg)
            }
            
            // Bottom action bar
            bottomActionBar(text: text)
        }
        .background(DesignSystem.Colors.background)
        .overlay(alignment: .bottom) {
            if viewModel.showCopiedToast {
                toast("Copied!")
            }
        }
    }
    
    @ViewBuilder
    private func htmlContent(_ html: String) -> some View {
        if let attributedString = parseHTML(html) {
            Text(attributedString)
                .foregroundStyle(DesignSystem.Colors.foreground)
        } else {
            // Fallback: strip HTML tags and show plain text
            Text(html.strippingHTMLTags())
                .font(DesignSystem.Typography.monoBody)
                .foregroundStyle(DesignSystem.Colors.foreground)
        }
    }
    
    private func parseHTML(_ html: String) -> AttributedString? {
        let data = Data(html.utf8)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        guard let nsAttributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) else {
            return nil
        }
        
        var attributedString = AttributedString(nsAttributedString)
        
        // Apply design system font as base if no font is set
        attributedString.font = DesignSystem.Typography.monoBody
        
        return attributedString
    }
    
    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Received")
                    .font(DesignSystem.Typography.body)
                    .fontWeight(.bold)
                    .foregroundStyle(DesignSystem.Colors.foreground)
                
                Text("from MacBook Pro · just now")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }
            
            Spacer()
            
            Button("Done") {
                viewModel.onComplete()
            }
            .font(DesignSystem.Typography.h4)
            .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
    }
    
    private func bottomActionBar(text: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            // Copy button (primary)
            Button(action: {
                UIPasteboard.general.string = text
                withAnimation {
                    viewModel.showCopiedToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation {
                        viewModel.showCopiedToast = false
                    }
                }
            }) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 15))
                    Text(viewModel.showCopiedToast ? "Copied!" : "Copy to Clipboard")
                        .font(DesignSystem.Typography.h4)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.md)
                .background(viewModel.showCopiedToast ? DesignSystem.Colors.success : DesignSystem.Colors.primary)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.button))
            }
            
            // Share button (secondary) - using standard iOS share icon to match design
            Button(action: { shareCurrentContent() }) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15))
                    Text("Share Content")
                        .font(DesignSystem.Typography.h4)
                }
                .foregroundStyle(DesignSystem.Colors.foreground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.button))
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.background)
        .overlay(alignment: .top) {
            Divider()
        }
    }
    
    private func toast(_ message: String) -> some View {
        Text(message)
            .font(DesignSystem.Typography.body)
            .foregroundStyle(.white)
            .padding(.horizontal, DesignSystem.Spacing.xl)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(Capsule().fill(DesignSystem.Colors.foreground.opacity(0.8)))
            .padding(.bottom, DesignSystem.Spacing.xl)
            .transition(.move(edge: .bottom).combined(with: .opacity))
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

private extension String {
    func strippingHTMLTags() -> String {
        // Use NSAttributedString to strip HTML tags
        let data = Data(self.utf8)
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        if let attributedString = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributedString.string
        }
        
        // Fallback: simple regex strip
        return self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
    }
}
#endif
