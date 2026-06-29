import SwiftUI
import WebKit

public struct RichTextReceiveView: View {
    let html: String
    @State private var showCopiedToast = false

    public init(html: String) {
        self.html = html
    }

    public var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            RichTextWebView(html: html)

            PrimaryButton(title: showCopiedToast ? "Copied!" : "Copy to Clipboard", icon: "doc.on.doc", style: .secondary) {
                copyToClipboard()
            }
        }
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                toast("Copied to clipboard")
            }
        }
    }

    private func copyToClipboard() {
        guard let data = html.data(using: .utf8) else { return }
        UIPasteboard.general.setData(data, forPasteboardType: "public.html")

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

struct RichTextWebView: UIViewRepresentable {
    let html: String

    class Coordinator {
        var lastHTML: String?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = true
        webView.loadHTMLString(html, baseURL: nil)
        context.coordinator.lastHTML = html
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard html != context.coordinator.lastHTML else {
            return
        }
        context.coordinator.lastHTML = html
        uiView.loadHTMLString(html, baseURL: nil)
    }
}