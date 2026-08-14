import Foundation

public enum CommentStyle {
    case line(String)
    case block(String, String)

    public static func forLanguage(_ id: String) -> CommentStyle {
        switch id {
        case "python", "bash", "ruby", "toml", "yaml":
            return .line("#")
        case "html", "xml", "markdown":
            return .block("<!--", "-->")
        case "css":
            return .block("/*", "*/")
        case "lua": return .line("--")
        case "batch": return .line("REM")
        case "powershell": return .line("#")
        case "ini", "toml", "yaml": return .line("#")
        case "sql": return .line("--")
        default:
            return .line("//")
        }
    }
}

public enum TextTransforms {
    public static func uppercase(_ text: String) -> String { text.uppercased() }
    public static func lowercase(_ text: String) -> String { text.lowercased() }

    public static func invertCase(_ text: String) -> String {
        String(text.map { ch in
            if ch.isUppercase { return Character(ch.lowercased()) }
            if ch.isLowercase { return Character(ch.uppercased()) }
            return ch
        })
    }

    /// Splits text into lines, preserving the dominant EOL style for re-joining.
    static func splitLinesPreservingEOL(_ text: String) -> (lines: [String], eol: String) {
        if text.contains("\r\n") {
            return (text.components(separatedBy: "\n").map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }, "\r\n")
        }
        if text.contains("\r") {
            return (text.components(separatedBy: "\r"), "\r")
        }
        return (text.components(separatedBy: "\n"), "\n")
    }

    public static func trimTrailingSpaces(_ text: String) -> String {
        let (lines, eol) = splitLinesPreservingEOL(text)
        return lines
            .map { line in
                var end = line.endIndex
                while end > line.startIndex {
                    let prev = line.index(before: end)
                    if line[prev] == " " || line[prev] == "\t" {
                        end = prev
                    } else {
                        break
                    }
                }
                return String(line[..<end])
            }
            .joined(separator: eol)
    }

    public static func sortLines(_ text: String, descending: Bool, unique: Bool) -> String {
        let split = splitLinesPreservingEOL(text)
        var lines = split.lines
        let eol = split.eol
        // NSString hasSuffix — Swift String.hasSuffix treats "\r\n" as one grapheme.
        let nsText = text as NSString
        let hadTrailingNewline = nsText.hasSuffix("\n") || nsText.hasSuffix("\r")
        // Keep last empty if trailing newline only as marker
        if hadTrailingNewline, lines.last == "" {
            lines.removeLast()
        }
        lines.sort { descending ? $0 > $1 : $0 < $1 }
        if unique {
            var seen = Set<String>()
            lines = lines.filter { seen.insert($0).inserted }
        }
        var out = lines.joined(separator: eol)
        if hadTrailingNewline { out += eol }
        return out
    }

    public static func toggleLineComments(in text: String, selection: NSRange, style: CommentStyle) -> (text: String, selection: NSRange) {
        guard case .line(let marker) = style else {
            return toggleBlockComment(in: text, selection: selection, style: style)
        }
        let ns = text as NSString
        let startLine = TextGeometry.lineNumber(at: selection.location, in: text)
        let endLoc = selection.location + max(selection.length, 0)
        let endLine = selection.length == 0
            ? startLine
            : TextGeometry.lineNumber(at: max(selection.location, endLoc - 1), in: text)

        var allCommented = true
        for line in startLine...endLine {
            let content = TextGeometry.contentRangeOfLine(line, in: text)
            let lineText = ns.substring(with: content)
            let trimmed = lineText.trimmingCharacters(in: .whitespaces)
            if !trimmed.hasPrefix(marker) {
                allCommented = false
                break
            }
        }

        let mutable = NSMutableString(string: text)
        for line in (startLine...endLine).reversed() {
            let content = TextGeometry.contentRangeOfLine(line, in: mutable as String)
            let lineText = (mutable as NSString).substring(with: content)
            if allCommented {
                if let range = lineText.range(of: marker) {
                    let prefix = lineText[..<range.lowerBound]
                    let wsCount = prefix.filter { $0 == " " || $0 == "\t" }.count
                    // Remove first marker after leading whitespace
                    if let markerRange = lineText.range(of: marker) {
                        let start = lineText.distance(from: lineText.startIndex, to: markerRange.lowerBound)
                        var len = marker.count
                        let after = lineText.index(markerRange.upperBound, offsetBy: 0, limitedBy: lineText.endIndex) ?? lineText.endIndex
                        if after < lineText.endIndex, lineText[after] == " " { len += 1 }
                        mutable.deleteCharacters(in: NSRange(location: content.location + start, length: len))
                        _ = wsCount
                    }
                }
            } else {
                let indent = lineText.prefix(while: { $0 == " " || $0 == "\t" }).count
                mutable.insert(marker + " ", at: content.location + indent)
            }
        }
        return (mutable as String, selection)
    }

    private static func toggleBlockComment(in text: String, selection: NSRange, style: CommentStyle) -> (text: String, selection: NSRange) {
        guard case .block(let open, let close) = style else { return (text, selection) }
        let ns = text as NSString
        if selection.length > 0 {
            let selected = ns.substring(with: selection)
            let mutable = NSMutableString(string: text)
            if selected.hasPrefix(open), selected.hasSuffix(close) {
                var inner = selected
                inner.removeFirst(open.count)
                inner.removeLast(close.count)
                if inner.hasPrefix(" ") { inner.removeFirst() }
                if inner.hasSuffix(" ") { inner.removeLast() }
                mutable.replaceCharacters(in: selection, with: inner)
                return (mutable as String, NSRange(location: selection.location, length: (inner as NSString).length))
            } else {
                let wrapped = "\(open) \(selected) \(close)"
                mutable.replaceCharacters(in: selection, with: wrapped)
                return (mutable as String, NSRange(location: selection.location, length: (wrapped as NSString).length))
            }
        }
        return (text, selection)
    }

    public static func joinLines(at location: Int, in text: String, separator: String = " ") -> (text: String, selection: NSRange) {
        let line = TextGeometry.lineNumber(at: location, in: text)
        let total = TextGeometry.lineCount(of: text)
        // Phantom empty last line from a trailing newline — joining onto it is a no-op.
        let lastRealLine = (text.hasSuffix("\n") || text.hasSuffix("\r")) ? max(1, total - 1) : total
        guard line < lastRealLine else { return (text, NSRange(location: location, length: 0)) }
        let upper = TextGeometry.rangeOfLine(line, in: text)
        let lower = TextGeometry.rangeOfLine(line + 1, in: text)
        let ns = text as NSString
        let first = ns.substring(with: upper).trimmingCharacters(in: CharacterSet.newlines)
        let second = ns.substring(with: lower).trimmingCharacters(in: CharacterSet.newlines)
        let joined = first + separator + second
        let mutable = NSMutableString(string: text)
        let replaceRange = NSRange(location: upper.location, length: (lower.location + lower.length) - upper.location)
        // Preserve a trailing newline only when the lower line actually had one.
        let hadTrailingEOL = ns.substring(with: lower).hasSuffix("\n") || ns.substring(with: lower).hasSuffix("\r")
        mutable.replaceCharacters(in: replaceRange, with: joined + (hadTrailingEOL ? "\n" : ""))
        return (mutable as String, NSRange(location: upper.location + (joined as NSString).length, length: 0))
    }

    public static func splitLine(at location: Int, in text: String, columns: [Int]) -> (text: String, selection: NSRange) {
        let line = TextGeometry.lineNumber(at: location, in: text)
        let content = TextGeometry.contentRangeOfLine(line, in: text)
        let ns = text as NSString
        let lineText = ns.substring(with: content)
        let col = TextGeometry.column(at: location, in: text)
        let splitAt = max(1, min(col, (lineText as NSString).length + 1))
        let mutable = NSMutableString(string: text)
        let insert = "\n"
        mutable.insert(insert, at: content.location + splitAt - 1)
        return (mutable as String, NSRange(location: content.location + splitAt, length: 0))
    }

    public static func removeBlankLines(_ text: String) -> String {
        let (lines, eol) = splitLinesPreservingEOL(text)
        return lines
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: eol)
    }

    public static func transposeLine(at location: Int, in text: String) -> (text: String, selection: NSRange)? {
        let line = TextGeometry.lineNumber(at: location, in: text)
        let total = TextGeometry.lineCount(of: text)
        let nsText = text as NSString
        let hasTrailingEOL = nsText.hasSuffix("\n") || nsText.hasSuffix("\r")
        let lastRealLine = hasTrailingEOL ? max(1, total - 1) : total
        guard line < lastRealLine else { return nil }
        let a = TextGeometry.rangeOfLine(line, in: text)
        let b = TextGeometry.rangeOfLine(line + 1, in: text)
        let ns = text as NSString
        let chunkA = ns.substring(with: a)
        let chunkB = ns.substring(with: b)
        let combined = NSRange(location: a.location, length: (b.location + b.length) - a.location)
        let combinedText = ns.substring(with: combined)
        let eol = combinedText.contains("\r\n") ? "\r\n" : (combinedText.contains("\r") ? "\r" : "\n")
        let hadTrailingEOL = combinedText.hasSuffix("\r\n") || combinedText.hasSuffix("\n") || combinedText.hasSuffix("\r")
        let swapped = stripTrailingEOL(chunkB) + eol + stripTrailingEOL(chunkA) + (hadTrailingEOL ? eol : "")
        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: combined, with: swapped)
        let newOffset = a.location + (stripTrailingEOL(chunkB) as NSString).length
        return (mutable as String, NSRange(location: newOffset, length: 0))
    }

    private static func stripTrailingEOL(_ line: String) -> String {
        let ns = line as NSString
        if ns.hasSuffix("\r\n") { return ns.substring(to: ns.length - 2) }
        if ns.hasSuffix("\n") || ns.hasSuffix("\r") { return ns.substring(to: ns.length - 1) }
        return line
    }

    public static func characterInfo(at location: Int, in text: String) -> (char: String, code: UInt32, hex: String)? {
        let ns = text as NSString
        guard location >= 0, location < ns.length else { return nil }
        let pair = ns.rangeOfComposedCharacterSequence(at: location)
        let ch = ns.substring(with: pair)
        guard let scalar = ch.unicodeScalars.first else { return nil }
        let code = scalar.value
        return (ch, code, String(format: "U+%04X", code))
    }
}

public enum BraceMatcher {
    private static let pairs: [Character: Character] = [
        "(": ")", "[": "]", "{": "}", "<": ">"
    ]
    private static let closers: Set<Character> = [")", "]", "}", ">"]

    public static func matchingRange(at location: Int, in text: String) -> NSRange? {
        let ns = text as NSString
        guard ns.length > 0 else { return nil }
        let loc = min(max(location, 0), ns.length)
        // Prefer character before caret, else at caret
        let candidates = [loc - 1, loc].filter { $0 >= 0 && $0 < ns.length }
        for idx in candidates {
            let scalars = ns.substring(with: NSRange(location: idx, length: 1))
            guard let ch = scalars.first else { continue }
            if let close = pairs[ch] {
                return findMatch(openIndex: idx, open: ch, close: close, text: ns, forward: true)
            }
            if closers.contains(ch), let open = pairs.first(where: { $0.value == ch })?.key {
                return findMatch(openIndex: idx, open: open, close: ch, text: ns, forward: false)
            }
        }
        return nil
    }

    private static func findMatch(
        openIndex: Int,
        open: Character,
        close: Character,
        text: NSString,
        forward: Bool
    ) -> NSRange? {
        var depth = 0
        if forward {
            for i in openIndex..<text.length {
                let c = text.substring(with: NSRange(location: i, length: 1)).first
                if c == open { depth += 1 }
                else if c == close {
                    depth -= 1
                    if depth == 0 {
                        return NSRange(location: openIndex, length: i - openIndex + 1)
                    }
                }
            }
        } else {
            for i in stride(from: openIndex, through: 0, by: -1) {
                let c = text.substring(with: NSRange(location: i, length: 1)).first
                if c == close { depth += 1 }
                else if c == open {
                    depth -= 1
                    if depth == 0 {
                        return NSRange(location: i, length: openIndex - i + 1)
                    }
                }
            }
        }
        return nil
    }
}
