import Foundation

public struct SessionTab: Codable, Equatable {
    public var path: String?
    public var untitledText: String?
    public var languageID: String
    public var encoding: String
    public var eol: String
    public var caret: Int
    public var bookmarks: [Int]
    public var kind: String

    public init(
        path: String? = nil,
        untitledText: String? = nil,
        languageID: String,
        encoding: String,
        eol: String,
        caret: Int,
        bookmarks: [Int],
        kind: String = "text"
    ) {
        self.path = path
        self.untitledText = untitledText
        self.languageID = languageID
        self.encoding = encoding
        self.eol = eol
        self.caret = caret
        self.bookmarks = bookmarks
        self.kind = kind
    }

    enum CodingKeys: String, CodingKey {
        case path, untitledText, languageID, encoding, eol, caret, bookmarks, kind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        untitledText = try container.decodeIfPresent(String.self, forKey: .untitledText)
        languageID = try container.decode(String.self, forKey: .languageID)
        encoding = try container.decode(String.self, forKey: .encoding)
        eol = try container.decode(String.self, forKey: .eol)
        caret = try container.decode(Int.self, forKey: .caret)
        bookmarks = try container.decode([Int].self, forKey: .bookmarks)
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "text"
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(path, forKey: .path)
        try container.encodeIfPresent(untitledText, forKey: .untitledText)
        try container.encode(languageID, forKey: .languageID)
        try container.encode(encoding, forKey: .encoding)
        try container.encode(eol, forKey: .eol)
        try container.encode(caret, forKey: .caret)
        try container.encode(bookmarks, forKey: .bookmarks)
        try container.encode(kind, forKey: .kind)
    }
}

public struct EditorSession: Codable, Equatable {
    public var tabs: [SessionTab]
    public var activeIndex: Int
    public var columnMode: Bool
    public var showDocumentMap: Bool
    public var showFunctionList: Bool

    public init(
        tabs: [SessionTab],
        activeIndex: Int,
        columnMode: Bool = false,
        showDocumentMap: Bool = false,
        showFunctionList: Bool = false
    ) {
        self.tabs = tabs
        self.activeIndex = activeIndex
        self.columnMode = columnMode
        self.showDocumentMap = showDocumentMap
        self.showFunctionList = showFunctionList
    }
}

public enum SessionManager {
    private static var autosaveURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent(AppIdentity.supportFolder, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("LastSession.json")
    }

    /// Moves a corrupt autosave aside so it stops failing every launch. Returns the new path.
    public static func quarantineCorruptAutosave() -> String? {
        let source = autosaveURL
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let target = source.deletingLastPathComponent()
            .appendingPathComponent("LastSession.corrupt-\(stamp.string(from: Date())).json")
        do {
            try FileManager.default.moveItem(at: source, to: target)
            return target.path
        } catch {
            return nil
        }
    }

    public static func save(_ session: EditorSession, to url: URL? = nil) throws {
        let target = url ?? autosaveURL
        let data = try JSONEncoder().encode(session)
        try data.write(to: target, options: .atomic)
    }

    public static func load(from url: URL? = nil) throws -> EditorSession {
        let target = url ?? autosaveURL
        let data = try Data(contentsOf: target)
        return try JSONDecoder().decode(EditorSession.self, from: data)
    }

    public static var hasAutosave: Bool {
        FileManager.default.fileExists(atPath: autosaveURL.path)
    }
}
