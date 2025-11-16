import SwiftUI
import WebKit

struct WebTabView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        context.coordinator.webView = webView
        load(url, into: webView, coordinator: context.coordinator)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard context.coordinator.currentURL != url else { return }
        load(url, into: nsView, coordinator: context.coordinator)
    }

    private func load(_ url: URL, into webView: WKWebView, coordinator: Coordinator) {
        coordinator.currentURL = url
        webView.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject {
        weak var webView: WKWebView?
        var currentURL: URL?
    }
}
