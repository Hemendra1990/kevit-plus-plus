import AppKit
import WebKit

/// Interactive JSON tree (collapse/expand, search, type badges, path
/// breadcrumb) hosted in `Resources/JsonView/` and served over the same
/// `snpphost://` scheme as the Markdown and Excalidraw hosts.
final class JsonPreviewViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    private(set) var webView: WKWebView!
    private let schemeHandler = LocalHostSchemeHandler()

    private var pendingJSON: String?
    private var jsReady = false
    private var didStartHostLoad = false
    private var missingLabel: NSTextField?

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: LocalHostSchemeHandler.scheme)
        config.userContentController.add(self, name: "jsonReady")
        config.userContentController.add(self, name: "jsonError")
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let boot = WKUserScript(
            source: """
            window.addEventListener('error', function(e) {
              try { webkit.messageHandlers.jsonError.postMessage(String(e.message)); } catch (x) {}
            });
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(boot)

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

    func loadJSON(_ text: String) {
        _ = view
        pendingJSON = text
        startHostIfNeeded()
        applyPending()
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

    func notifyVisible() {
        startHostIfNeeded()
        guard jsReady else { return }
        webView.evaluateJavaScript("window.dispatchEvent(new Event('resize'));")
    }

    func applyChromeTheme() {
        let dark = ThemeManager.shared.current.isDark
        webView?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let theme = dark ? "dark" : "light"
        webView?.evaluateJavaScript("window.snppSetTheme && window.snppSetTheme('\(theme)');")
    }

    private func startHostIfNeeded() {
        if didStartHostLoad { return }
        guard pendingJSON != nil else { return }
        didStartHostLoad = true
        guard Self.hostDirectory() != nil else {
            showPlaceholder(glyph: "⚠", title: "JSON viewer missing", message: "Resources/JsonView should ship inside the app bundle.")
            return
        }
        var components = URLComponents()
        components.scheme = LocalHostSchemeHandler.scheme
        components.host = "host"
        components.path = "/JsonView/index.html"
        if let url = components.url {
            missingLabel?.removeFromSuperview()
            missingLabel = nil
            webView.load(URLRequest(url: url))
        }
    }

    private func applyPending() {
        guard jsReady, let json = pendingJSON else { return }
        applyChromeTheme()
        webView.callAsyncJavaScript(
            "return window.snppSetJson ? window.snppSetJson({ json: JSON.stringify(text) }) : 'no';",
            arguments: ["text": json],
            in: nil,
            in: .page
        ) { _ in }
    }

    private static func hostDirectory() -> URL? {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("JsonView"))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/JsonView"))
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/JsonView"))

        var walk = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<8 {
            candidates.append(walk.appendingPathComponent("Resources/JsonView"))
            walk.deleteLastPathComponent()
        }
        for dir in candidates {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("index.html").path) {
                return dir
            }
        }
        return nil
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showPlaceholder(glyph: "⚠", title: "JSON viewer failed to load", message: error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showPlaceholder(glyph: "⚠", title: "JSON viewer failed to load", message: error.localizedDescription)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let scheme = navigationAction.request.url?.scheme?.lowercased()
        if scheme == LocalHostSchemeHandler.scheme || scheme == "about" || scheme == nil {
            decisionHandler(.allow)
        } else {
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

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "jsonReady":
            jsReady = true
            applyPending()
        case "jsonError":
            // Parse errors are rendered in-page; nothing to surface natively.
            break
        default:
            break
        }
    }
}
