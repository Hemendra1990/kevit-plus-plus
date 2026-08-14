import AppKit
import WebKit

final class DrawingViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    var onSceneChanged: ((String) -> Void)?
    private(set) var lastSceneJSON: String = Document.emptyDrawingJSON
    private(set) var webView: WKWebView!
    private let schemeHandler = LocalHostSchemeHandler()

    private var pendingScene: String?
    private var ignoreChangeCount = 0
    private var debounceWork: DispatchWorkItem?
    private var jsReady = false
    private var didStartHostLoad = false
    private var missingLabel: NSTextField?

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(schemeHandler, forURLScheme: LocalHostSchemeHandler.scheme)
        config.userContentController.add(self, name: "drawingChanged")
        config.userContentController.add(self, name: "drawingReady")
        config.userContentController.add(self, name: "drawingError")
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let boot = WKUserScript(
            source: """
            window.addEventListener('error', function(e) {
              try { webkit.messageHandlers.drawingError.postMessage(String(e.message)); } catch (x) {}
            });
            window.addEventListener('unhandledrejection', function(e) {
              try { webkit.messageHandlers.drawingError.postMessage(String(e.reason)); } catch (x) {}
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
        webView.appearance = NSAppearance(named: .aqua)
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = .white
        }
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

    func loadScene(_ json: String) {
        _ = view
        let scene = json.isEmpty ? Document.emptyDrawingJSON : json
        lastSceneJSON = scene
        pendingScene = scene
        ignoreChangeCount = 3
        startHostIfNeeded()
        if jsReady {
            applyPendingScene()
            notifyVisible()
        }
    }

    func notifyVisible() {
        startHostIfNeeded()
        guard jsReady else { return }
        webView.evaluateJavaScript(
            "window.dispatchEvent(new Event('resize')); window.snppRefresh && window.snppRefresh();"
        )
    }

    func flushPendingChanges() {
        debounceWork?.cancel()
        debounceWork = nil
    }

    /// The JS exporters return promises, so they need `callAsyncJavaScript`.
    /// `evaluateJavaScript` hands back the unresolved promise and the cast fails.
    func exportPNG(completion: @escaping (Data?) -> Void) {
        callAsync("return window.snppExportPNG ? await window.snppExportPNG() : null;") { value in
            guard let b64 = value as? String, let data = Data(base64Encoded: b64) else {
                completion(nil)
                return
            }
            completion(data)
        }
    }

    func exportSVG(completion: @escaping (String?) -> Void) {
        callAsync("return window.snppExportSVG ? await window.snppExportSVG() : null;") { value in
            completion(value as? String)
        }
    }

    private func callAsync(_ body: String, completion: @escaping (Any?) -> Void) {
        webView.callAsyncJavaScript(body, arguments: [:], in: nil, in: .page) { result in
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

    func applyChromeTheme() {
        let theme = ThemeManager.shared.current.isDark ? "dark" : "light"
        webView?.evaluateJavaScript("window.snppSetTheme && window.snppSetTheme('\(theme)')")
    }

    private func startHostIfNeeded() {
        if didStartHostLoad { return }
        guard pendingScene != nil else { return }
        didStartHostLoad = true
        loadHost()
    }

    private func loadHost() {
        guard Self.hostDirectory() != nil else {
            showMissingHost()
            return
        }
        var components = URLComponents()
        components.scheme = LocalHostSchemeHandler.scheme
        components.host = "host"
        components.path = "/index.html"
        guard let url = components.url else {
            showMissingHost()
            return
        }
        missingLabel?.removeFromSuperview()
        missingLabel = nil
        webView.load(URLRequest(url: url))
    }

    private func showMissingHost() {
        showOverlay("Excalidraw host missing. Run Scripts/build-excalidraw.sh, then rebundle the app.")
    }

    private func applyPendingScene() {
        guard jsReady, let scene = pendingScene else { return }
        applyChromeTheme()
        guard let payload = try? String(data: JSONEncoder().encode(scene), encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.snppSetScene && window.snppSetScene(\(payload))")
    }

    static func hostDirectory() -> URL? {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("Excalidraw"))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Excalidraw"))
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Excalidraw"))

        var walk = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<8 {
            candidates.append(walk.appendingPathComponent("Resources/Excalidraw"))
            walk.deleteLastPathComponent()
        }

        for dir in candidates {
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("index.html").path) {
                return dir
            }
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        showOverlay("Drawing failed to load: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showOverlay("Drawing failed to load: \(error.localizedDescription)")
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

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if url.isFileURL || url.scheme == "about" || url.scheme == LocalHostSchemeHandler.scheme {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        switch message.name {
        case "drawingReady":
            jsReady = true
            applyPendingScene()
            notifyVisible()
        case "drawingError":
            guard !jsReady else { return }
            let detail = (message.body as? String) ?? "unknown error"
            showOverlay("Drawing error: \(detail)")
        case "drawingChanged":
            guard let json = message.body as? String else { return }
            lastSceneJSON = json
            if ignoreChangeCount > 0 {
                ignoreChangeCount -= 1
                return
            }
            debounceWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.onSceneChanged?(json)
            }
            debounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        default:
            break
        }
    }
}
