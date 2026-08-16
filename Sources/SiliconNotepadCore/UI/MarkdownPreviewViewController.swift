import AppKit
import WebKit

/// Renders Markdown in a WKWebView using the bundled host at
/// `Resources/Markdown/` (served over `snpphost://`).
///
/// This controller is the single Markdown renderer for the whole app: the
/// preview pane and "Export HTML…" both go through the same `preview.js`
/// pipeline, so what the user previews is byte-identical to the export.
final class MarkdownPreviewViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    private(set) var webView: WKWebView!
    private let schemeHandler = LocalHostSchemeHandler()

    private var pendingMarkdown: String?
    private var pendingPlaceholder: (glyph: String, title: String, message: String)?
    private var jsReady = false
    private var didStartHostLoad = false
    private var missingLabel: NSTextField?
    private var readyCallbacks: [() -> Void] = []

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: LocalHostSchemeHandler.scheme)
        config.userContentController.add(self, name: "markdownReady")
        config.userContentController.add(self, name: "markdownError")
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let boot = WKUserScript(
            source: """
            window.addEventListener('error', function(e) {
              try { webkit.messageHandlers.markdownError.postMessage(String(e.message)); } catch (x) {}
            });
            window.addEventListener('unhandledrejection', function(e) {
              try { webkit.messageHandlers.markdownError.postMessage(String(e.reason)); } catch (x) {}
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

    // MARK: - Public API

    /// Renders `markdown` in the pane (replacing any placeholder). Loads the
    /// host lazily; content is applied once JS reports ready.
    func loadMarkdown(_ markdown: String) {
        _ = view
        pendingMarkdown = markdown
        pendingPlaceholder = nil
        startHostIfNeeded()
        applyPending()
    }

    /// Shows a centered muted message instead of content (e.g. "Not a Markdown file").
    func showPlaceholder(glyph: String, title: String, message: String) {
        _ = view
        pendingPlaceholder = (glyph, title, message)
        pendingMarkdown = nil
        startHostIfNeeded()
        applyPending()
    }

    /// Runs `completion` once the renderer is live. The host loads on demand,
    /// so export works even when the preview pane has never been shown.
    func prepare(completion: (() -> Void)? = nil) {
        _ = view
        startHostIfNeeded()
        guard let completion else { return }
        if jsReady {
            completion()
        } else {
            readyCallbacks.append(completion)
        }
    }

    /// Standalone HTML document for `markdown`, produced by the exact same
    /// renderer + stylesheet the preview shows.
    func exportHTML(_ markdown: String, completion: @escaping (String?) -> Void) {
        prepare { [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            self.callAsync(
                "return window.snppExportHTML ? window.snppExportHTML({ json: JSON.stringify(md) }) : null;",
                arguments: ["md": markdown]
            ) { value in
                completion(value as? String)
            }
        }
    }

    /// Re-render the current content (e.g. after the host was reloaded).
    func refresh() {
        applyPending()
    }

    func notifyVisible() {
        startHostIfNeeded()
        guard jsReady else { return }
        webView.evaluateJavaScript("window.snppRefresh && window.snppRefresh();")
    }

    func applyChromeTheme() {
        let dark = ThemeManager.shared.current.isDark
        webView?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let theme = dark ? "dark" : "light"
        webView?.evaluateJavaScript("window.snppSetTheme && window.snppSetTheme('\(theme)');")
    }

    // MARK: - Private

    private func startHostIfNeeded() {
        if didStartHostLoad { return }
        guard pendingMarkdown != nil || pendingPlaceholder != nil || !readyCallbacks.isEmpty else { return }
        didStartHostLoad = true
        loadHost()
    }

    private func loadHost() {
        guard Self.hostDirectory() != nil else {
            showOverlay("Markdown host missing. Resources/Markdown should ship inside the app bundle.")
            return
        }
        var components = URLComponents()
        components.scheme = LocalHostSchemeHandler.scheme
        components.host = "host"
        components.path = "/Markdown/index.html"
        guard let url = components.url else {
            showOverlay("Markdown host URL could not be built.")
            return
        }
        missingLabel?.removeFromSuperview()
        missingLabel = nil
        webView.load(URLRequest(url: url))
    }

    private func applyPending() {
        guard jsReady else { return }
        applyChromeTheme()
        if let placeholder = pendingPlaceholder {
            callAsync(
                "return window.snppSetPlaceholder ? window.snppSetPlaceholder(g, t, m) : 'no';",
                arguments: ["g": placeholder.glyph, "t": placeholder.title, "m": placeholder.message]
            ) { _ in }
        } else if let markdown = pendingMarkdown {
            callAsync(
                "return window.snppSetPreviewContent ? window.snppSetPreviewContent({ json: JSON.stringify(md) }) : 'no';",
                arguments: ["md": markdown]
            ) { _ in }
        }
    }

    private func callAsync(
        _ body: String,
        arguments: [String: Any],
        completion: @escaping (Any?) -> Void
    ) {
        webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let value):
                    completion(value)
                case .failure:
                    completion(nil)
                }
            }
        }
    }

    private static func hostDirectory() -> URL? {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("Markdown"))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Markdown"))
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Markdown"))

        var walk = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<8 {
            candidates.append(walk.appendingPathComponent("Resources/Markdown"))
            walk.deleteLastPathComponent()
        }

        for dir in candidates {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("index.html").path) {
                return dir
            }
        }
        return nil
    }

    private func showOverlay(_ text: String) {
        missingLabel?.removeFromSuperview()
        let label = NSTextField(wrappingLabelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        webView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: webView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: webView.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: webView.widthAnchor, constant: -40)
        ])
        missingLabel = label
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showOverlay("Markdown preview failed to load: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showOverlay("Markdown preview failed to load: \(error.localizedDescription)")
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        switch url.scheme?.lowercased() {
        case LocalHostSchemeHandler.scheme, "about":
            decisionHandler(.allow)
        case "http", "https", "mailto":
            // External links open in the user's browser, never in the preview pane.
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
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

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "markdownReady":
            jsReady = true
            applyPending()
            let callbacks = readyCallbacks
            readyCallbacks.removeAll()
            callbacks.forEach { $0() }
        case "markdownError":
            guard !jsReady else { return }
            let detail = (message.body as? String) ?? "unknown error"
            showOverlay("Markdown error: \(detail)")
        default:
            break
        }
    }
}
