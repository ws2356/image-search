import SwiftUI
import WebKit

public struct RichTextReceiveView: View {
    let html: String
    @State private var showCopiedToast = false
    
    public init(html: String) {
        self.html = html
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            RichTextWebView(html: html)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
            
            Button(action: copyToClipboard) {
                Label("Copy to Clipboard", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.top, 16)
        .overlay(alignment: .bottom) {
            if showCopiedToast {
                ToastView(message: "Copied to clipboard")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 100)
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

struct ToastView: View {
    let message: String
    
    var body: some View {
        Text(message)
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(8)
    }
}
