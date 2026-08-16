import AppKit

/// The three Markdown viewing arrangements. Kept as a standalone enum so any
/// future Markdown surface (quick-look panes, plugin windows, …) can share
/// the same vocabulary and switcher UI.
enum MarkdownViewMode: String, CaseIterable {
    case code
    case split
    case preview

    var label: String {
        switch self {
        case .code: return "Code"
        case .split: return "Split"
        case .preview: return "Preview"
        }
    }

    var tooltip: String {
        switch self {
        case .code: return "Show Markdown source only (⌥⌘1)"
        case .split: return "Show source and rendered preview side by side (⌥⌘2 or ⇧⌘V)"
        case .preview: return "Show rendered preview only (⌥⌘3)"
        }
    }
}

/// Conservative content sniffer: decides whether plain (non-`.md`) text
/// should be treated as Markdown. Every rule is weighted; the total must
/// clear `threshold` so ordinary prose with the odd dash or asterisk stays
/// plain text.
enum MarkdownDetector {
    static let threshold = 4.0

    static func looksLikeMarkdown(_ text: String) -> Bool {
        score(text) >= threshold
    }

    static func score(_ text: String) -> Double {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        if lines.count > 5000 {
            lines = Array(lines.prefix(2500)) + Array(lines.suffix(2500))
        }

        var s = 0.0
        var headingHits = 0
        var listHits = 0
        var orderedHits = 0
        var quoteHits = 0
        var previousLineHadPipes = false

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            // Fenced code block
            if line.hasPrefix("```") || line.hasPrefix("~~~") { s += 4; continue }

            // Table: a header row of pipes followed by a |---|---| separator
            if previousLineHadPipes, isTableSeparator(line) {
                s += 4
                previousLineHadPipes = false
                continue
            }
            previousLineHadPipes = !line.isEmpty
                && line.hasPrefix("|")
                && line.dropFirst().contains("|")

            // ATX heading: 1-6 '#' then a space then text ("#!" is a shebang)
            if isHeading(line) {
                s += headingHits == 0 ? 3 : 1
                headingHits += 1
                continue
            }

            // Checklist item: "- [ ]" / "- [x] done"
            if isListItem(line) {
                let afterMarker = line.dropFirst(2)
                if afterMarker.hasPrefix("[ ] ") || afterMarker.hasPrefix("[x] ") || afterMarker.hasPrefix("[X] ") {
                    s += 2
                    continue
                }
            }

            // Blockquote
            if line.hasPrefix("> "), quoteHits < 2 {
                s += 2
                quoteHits += 1
                continue
            }

            // Horizontal rule
            if isHorizontalRule(line) { s += 1; continue }

            // Lists (capped — prose dashes accumulate slowly)
            if isListItem(line), listHits < 3 {
                s += 1
                listHits += 1
                continue
            }
            if isOrderedItem(line), orderedHits < 3 {
                s += 1
                orderedHits += 1
            }
        }

        // Inline constructs over the whole text
        let inline = text.prefix(200_000)
        if inline.range(of: #"!\[[^\]\n]*\]\([^)\n]+\)"#, options: .regularExpression) != nil { s += 2 }
        if inline.range(of: #"\[[^\]\n]+\]\([^)\n]+\)"#, options: .regularExpression) != nil { s += 2 }
        if inline.range(of: #"\*\*[^*\n]+\*\*|__[^_\n]+__"#, options: .regularExpression) != nil { s += 2 }
        if inline.range(of: #"(^|\s)\*[^*\n\s][^*\n]*\*($|\s)"#, options: .regularExpression) != nil { s += 1 }

        return s
    }

    /// `#` … `######` followed by a space and non-empty text. Shebangs don't count.
    private static func isHeading(_ line: String) -> Bool {
        guard line.hasPrefix("#"), !line.hasPrefix("#!") else { return false }
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 } else { break }
        }
        guard level <= 6 else { return false }
        let rest = line.dropFirst(level)
        guard rest.hasPrefix(" "), rest.dropFirst().contains(where: { !$0.isWhitespace }) else {
            return false
        }
        return true
    }

    private static func isListItem(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    private static func isOrderedItem(_ line: String) -> Bool {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return false }
        let rest = line.dropFirst(digits.count)
        return rest.hasPrefix(". ") || rest.hasPrefix(") ")
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: CharacterSet(charactersIn: "| "))
        guard t.contains("-"), !t.isEmpty else { return false }
        return t.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " || $0 == "|" }
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let t = line.filter { !$0.isWhitespace }
        guard t.count >= 3 else { return false }
        return t.allSatisfy { $0 == "-" } || t.allSatisfy { $0 == "*" } || t.allSatisfy { $0 == "_" }
    }
}

/// The draggable gap between editor and preview. Six points wide for a
/// forgiving grab area; the visual line is the layer background, re-tinted
/// on theme changes.
final class MarkdownDividerView: NSView {
    var orientation: NSUserInterfaceLayoutOrientation = .horizontal {
        didSet { resetCursorRects() }
    }
    var onDrag: ((CGFloat) -> Void)?

    private var dragStartLocation: NSPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        toolTip = "Drag to resize the editor and preview panes"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func applyTheme(_ theme: EditorTheme) {
        let color = theme.isDark
            ? NSColor(calibratedWhite: 0.32, alpha: 1)
            : NSColor(calibratedWhite: 0.78, alpha: 1)
        layer?.backgroundColor = color.cgColor
    }

    override func resetCursorRects() {
        let cursor: NSCursor
        switch orientation {
        case .horizontal: cursor = .resizeLeftRight
        case .vertical: cursor = .resizeUpDown
        @unknown default: cursor = .resizeLeftRight
        }
        addCursorRect(bounds, cursor: cursor)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = window?.convertPoint(toScreen: NSEvent.mouseLocation)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartLocation else { return }
        let now = window?.convertPoint(toScreen: NSEvent.mouseLocation) ?? start
        // Screen coordinates grow upward, so a downward drag is negative —
        // flip for vertical splits to keep "drag down = taller preview".
        let delta: CGFloat
        switch orientation {
        case .horizontal: delta = now.x - start.x
        case .vertical: delta = start.y - now.y
        @unknown default: delta = now.x - start.x
        }
        guard delta != 0 else { return }
        dragStartLocation = now
        onDrag?(delta)
    }
}
