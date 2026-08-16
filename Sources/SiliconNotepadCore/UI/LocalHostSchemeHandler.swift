import AppKit
import UniformTypeIdentifiers
import WebKit

/// Serves bundled web hosts (Excalidraw, Markdown preview) over a custom
/// `snpphost://` scheme so pages can load their scripts and assets as
/// same-origin resources. (file:// module fetches require private WebKit keys
/// that newer macOS removes.)
///
/// Paths resolve against the bundle's `Resources` directory first — so
/// `snpphost://markdown/index.html` finds `Resources/Markdown/index.html` —
/// and fall back to `Resources/Excalidraw/`, which keeps the Excalidraw host's
/// root-relative asset URLs (`/assets/...`) working unchanged.
final class LocalHostSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "snpphost"

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        if ProcessInfo.processInfo.environment["SNPP_DEBUG_HOST"] != nil {
            FileHandle.standardError.write(Data("SCHEME-REQ \(task.request.url?.absoluteString ?? "nil")\n".utf8))
        }
        guard
            let url = task.request.url,
            url.scheme == Self.scheme,
            let file = Self.resolveFile(for: url),
            let data = try? Data(contentsOf: file)
        else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let mime = Self.mimeType(forExtension: file.pathExtension)
        let headers = Self.httpHeaders(mimeType: mime, contentLength: data.count)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            task.didFailWithError(URLError(.cannotParseResponse))
            return
        }

        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html"
        case "js", "mjs": return "text/javascript"
        case "css": return "text/css"
        case "json": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "wasm": return "application/wasm"
        case "map": return "application/json"
        default:
            return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        }
    }

    static func httpHeaders(mimeType: String, contentLength: Int) -> [String: String] {
        let needsCharset =
            mimeType.hasPrefix("text/")
            || mimeType == "application/json"
            || mimeType == "application/javascript"
            || mimeType == "text/javascript"
        let contentType = needsCharset ? "\(mimeType); charset=utf-8" : mimeType
        return [
            "Content-Type": contentType,
            "Access-Control-Allow-Origin": "*",
            "Content-Length": "\(contentLength)",
            "Cache-Control": "no-cache"
        ]
    }

    static func fileURL(for request: URL, hostDirectory: URL) -> URL? {
        let path = request.path
        let relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard !relative.isEmpty else { return nil }

        let base = hostDirectory.standardizedFileURL
        let file = base.appendingPathComponent(relative).standardizedFileURL
        let basePath = base.path
        let filePath = file.path
        guard filePath == basePath || filePath.hasPrefix(basePath + "/") else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: filePath) else {
            return nil
        }
        return file
    }

    /// First match across the Resources roots and the legacy Excalidraw root
    /// (the Excalidraw host requests its assets with root-relative URLs).
    static func resolveFile(for request: URL) -> URL? {
        for dir in resourceDirectories() {
            if let file = fileURL(for: request, hostDirectory: dir) {
                return file
            }
        }
        return nil
    }

    /// Candidate base directories: the Resources root plus the Excalidraw
    /// subdir of each. The app bundle comes first, then the repo layout
    /// (`swift run` has no bundle, so walk up from the cwd).
    static func resourceDirectories() -> [URL] {
        var roots: [URL] = []
        if let resources = Bundle.main.resourceURL {
            roots.append(resources)
        }
        roots.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"))
        roots.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources"))

        var walk = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<8 {
            roots.append(walk.appendingPathComponent("Resources"))
            walk.deleteLastPathComponent()
        }

        var candidates: [URL] = []
        for root in roots {
            candidates.append(root)
            candidates.append(root.appendingPathComponent("Excalidraw"))
        }
        return candidates
    }
}
