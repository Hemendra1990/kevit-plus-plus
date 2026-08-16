import AppKit
import WebKit

/// Renders an HTML document in a sandboxed WKWebView. Uses `loadHTMLString`
/// with no base URL, so the page can style itself but cannot touch local
/// files; links and popups are routed out of the pane (browser / blocked).
/// Plugs into the same Code/Split/Preview + fullscreen pane machinery as the
/// Markdown preview.
final class HTMLPreviewViewController: NSViewController, WKNavigationDelegate, WKUIDelegate {
    private(set) var webView: WKWebView!
    private var pendingHTML: String?
    private var currentLoadGeneration = 0
    private var missingLabel: NSTextField?

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        webView = WKWebView(frame: container.bounds, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 13.3, *) {
            #if DEBUG
            webView.isInspectable = true
            #endif
        }
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        view = container
    }

    var contentView: NSView { view }

    /// Renders `html`, debounced by coalescing rapid calls (live typing).
    func loadHTML(_ html: String) {
        _ = view
        pendingHTML = html
        renderPending()
    }

    func showPlaceholder(glyph: String, title: String, message: String) {
        _ = view
        let label = NSTextField(wrappingLabelWithString: "\(glyph)  \(title)\n\(message)")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        missingLabel?.removeFromSuperview()
        webView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: webView.widthAnchor, constant: -40)
        ])
        missingLabel = label
    }

    private func renderPending() {
        guard let html = pendingHTML else { return }
        currentLoadGeneration += 1
        missingLabel?.removeFromSuperview()
        missingLabel = nil
        // A fresh data URL avoids loadHTMLString's back/forward side effects
        // for large documents while keeping the page originless (no file access).
        webView.loadHTMLString(html, baseURL: nil)
    }

    func notifyVisible() {
        webView.evaluateJavaScript("window.dispatchEvent(new Event('resize'));")
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        // about:blank/loadHTMLString navigations and same-document anchors.
        if url.scheme == nil || url.scheme == "about" {
            decisionHandler(.allow)
            return
        }
        switch url.scheme?.lowercased() {
        case "http", "https", "mailto":
            // Clicked links open in the default browser, never in the pane.
            if navigationAction.navigationType == .linkActivated {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        default:
            decisionHandler(.cancel)
        }
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showLoadError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showLoadError(error)
    }

    private func showLoadError(_ error: Error) {
        showPlaceholder(glyph: "⚠", title: "Render failed", message: error.localizedDescription)
    }
}
