import AppKit
import Foundation
import UniformTypeIdentifiers

enum DocumentKind: String, Equatable {
    case text
    case drawing
}

final class Document: NSObject {
    let id = UUID()
    var fileURL: URL?
    var text: String
    var encoding: TextEncodingKind
    var eol: EOLStyle
    var languageID: String
    var kind: DocumentKind
    var isDirty: Bool = false
    var isLanguageForced: Bool = false
    /// 1-based bookmarked line numbers
    var bookmarks: Set<Int> = []

    static let emptyDrawingJSON = """
    {"type":"excalidraw","version":2,"source":"app://kevitplusplus","elements":[],"appState":{"gridSize":null,"viewBackgroundColor":"#ffffff"},"files":{}}
    """

    var displayName: String {
        let name = fileURL?.lastPathComponent ?? (kind == .drawing ? "Untitled Drawing" : "Untitled")
        var base = isDirty ? "• \(name)" : name
        if let url = fileURL, !FileManager.default.fileExists(atPath: url.path), !isDirty {
            base += " (missing)"
        }
        return base
    }

    var plainDisplayName: String {
        fileURL?.lastPathComponent ?? (kind == .drawing ? "Untitled Drawing" : "Untitled")
    }

    /// True for `.md`-family files or any document whose language is forced to
    /// Markdown — the cases where the preview pane can render it.
    var isMarkdown: Bool {
        guard kind != .drawing else { return false }
        if let ext = fileURL?.pathExtension.lowercased(),
           ["md", "markdown", "mdown", "mkd"].contains(ext) {
            return true
        }
        return languageID == "markdown"
    }

    /// HTML by extension or language only (content detection lives in the
    /// preview-kind heuristic, which reports it as "detected").
    var isHTMLDocument: Bool {
        guard kind != .drawing else { return false }
        if let ext = fileURL?.pathExtension.lowercased(), ["html", "htm"].contains(ext) {
            return true
        }
        return languageID == "html"
    }

    var isJSONDocument: Bool {
        guard kind != .drawing else { return false }
        if let ext = fileURL?.pathExtension.lowercased(), ext == "json" {
            return true
        }
        return languageID == "json"
    }

    /// Strong content signal for extension-less HTML documents.
    var looksLikeHTMLContent: Bool {
        guard kind != .drawing else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("<!doctype html") || trimmed.hasPrefix("<html")
    }

    /// Parses as a JSON object/array — cheap enough for the preview heuristic
    /// because it only runs for documents without a JSON extension.
    var looksLikeJSONContent: Bool {
        guard kind != .drawing, text.utf8.count < 2_000_000 else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return false }
        return JsonFormatter.validate(text) == nil
    }

    init(
        fileURL: URL? = nil,
        text: String = "",
        encoding: TextEncodingKind = .utf8,
        eol: EOLStyle = .lf,
        languageID: String = "plaintext",
        kind: DocumentKind = .text
    ) {
        self.fileURL = fileURL
        self.text = text
        self.encoding = encoding
        self.eol = eol
        self.languageID = languageID
        self.kind = kind
    }

    static func newUntitled() -> Document {
        let encoding = Preferences.shared.defaultEncoding
        let eol = Preferences.shared.defaultEOL
        return Document(encoding: encoding, eol: eol)
    }

    static func newUntitledDrawing() -> Document {
        Document(
            text: emptyDrawingJSON,
            encoding: .utf8,
            eol: .lf,
            languageID: "plaintext",
            kind: .drawing
        )
    }

    static func looksLikeDrawing(url: URL, data: Data) -> Bool {
        if url.pathExtension.lowercased() == "excalidraw" {
            return true
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "excalidraw" else {
            return false
        }
        return true
    }

    static func open(url: URL) throws -> Document {
        let data = try Data(contentsOf: url)
        if looksLikeDrawing(url: url, data: data) {
            guard let text = String(data: data, encoding: .utf8) else {
                throw NSError(
                    domain: AppIdentity.errorDomain,
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to decode drawing file."]
                )
            }
            return Document(
                fileURL: url,
                text: text,
                encoding: .utf8,
                eol: .lf,
                languageID: "plaintext",
                kind: .drawing
            )
        }
        guard let detected = EncodingDetector.detect(data: data) else {
            throw NSError(
                domain: AppIdentity.errorDomain,
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to decode file."]
            )
        }
        let eol = EOLStyle.detect(in: detected.text)
        var language = LanguageRegistry.shared.languageID(forFilename: url.lastPathComponent)
        // Files with no meaningful extension still deserve Markdown treatment
        // (highlighting + preview) when their content clearly is Markdown.
        if language == "plaintext", MarkdownDetector.looksLikeMarkdown(detected.text) {
            language = "markdown"
        }
        return Document(
            fileURL: url,
            text: detected.text,
            encoding: detected.encoding,
            eol: eol,
            languageID: language
        )
    }

    func noteOpenedOnDisk() {
        FileMonitor.shared.snapshot(document: self)
    }

    func save(to url: URL? = nil) throws {
        let target = url ?? fileURL
        guard let target else {
            throw NSError(
                domain: AppIdentity.errorDomain,
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No file URL for save."]
            )
        }
        let data: Data
        let normalized: String
        if kind == .drawing {
            encoding = .utf8
            eol = .lf
            normalized = text
            data = Data(normalized.utf8)
        } else {
            normalized = EncodingDetector.normalizeEOL(text, to: eol)
            guard let encoded = EncodingDetector.encode(normalized, encoding: encoding) else {
                throw NSError(
                    domain: AppIdentity.errorDomain,
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to encode file."]
                )
            }
            data = encoded
        }
        try data.write(to: target, options: .atomic)
        fileURL = target
        text = normalized
        isDirty = false
        if kind != .drawing, !isLanguageForced {
            languageID = LanguageRegistry.shared.languageID(forExtension: target.pathExtension)
        }
        NSDocumentController.shared.noteNewRecentDocumentURL(target)
        FileMonitor.shared.snapshot(document: self)
    }

    func toggleBookmark(atLine line: Int) {
        if bookmarks.contains(line) {
            bookmarks.remove(line)
        } else {
            bookmarks.insert(line)
        }
    }

    func nextBookmark(after line: Int) -> Int? {
        bookmarks.sorted().first { $0 > line } ?? bookmarks.sorted().first
    }

    func previousBookmark(before line: Int) -> Int? {
        bookmarks.sorted().last { $0 < line } ?? bookmarks.sorted().last
    }

    var contentType: UTType {
        if kind == .drawing {
            return .excalidraw
        }
        if let ext = fileURL?.pathExtension, !ext.isEmpty,
           let type = UTType(filenameExtension: ext) {
            return type
        }
        return .plainText
    }
}

extension UTType {
    static let excalidraw = UTType(exportedAs: "app.kevit.excalidraw")
}
