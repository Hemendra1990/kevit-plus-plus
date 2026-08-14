import Foundation

public enum TextGeometry {
    /// 1-based line number for UTF-16 offset.
    public static func lineNumber(at location: Int, in text: String) -> Int {
        let ns = text as NSString
        let loc = min(max(location, 0), ns.length)
        var line = 1
        var i = 0
        while i < loc {
            let c = ns.character(at: i)
            if c == 10 {
                line += 1
            } else if c == 13 {
                line += 1
                if i + 1 < loc, ns.character(at: i + 1) == 10 { i += 1 }
            }
            i += 1
        }
        return line
    }

    public static func column(at location: Int, in text: String) -> Int {
        let ns = text as NSString
        let loc = min(max(location, 0), ns.length)
        var column = 1
        var i = 0
        while i < loc {
            let c = ns.character(at: i)
            if c == 10 || c == 13 {
                column = 1
                if c == 13, i + 1 < loc, ns.character(at: i + 1) == 10 { i += 1 }
            } else {
                column += 1
            }
            i += 1
        }
        return column
    }

    public static func lineCount(of text: String) -> Int {
        if text.isEmpty { return 1 }
        return lineNumber(at: (text as NSString).length, in: text)
    }

    /// UTF-16 range covering the whole line (1-based), including trailing newline except last line.
    public static func rangeOfLine(_ line: Int, in text: String) -> NSRange {
        let ns = text as NSString
        var current = 1
        var start = 0
        var i = 0
        while i < ns.length {
            if current == line { start = i; break }
            let c = ns.character(at: i)
            if c == 10 {
                current += 1
            } else if c == 13 {
                current += 1
                if i + 1 < ns.length, ns.character(at: i + 1) == 10 { i += 1 }
            }
            i += 1
            if i >= ns.length, current == line { start = i; break }
        }
        if current != line {
            // clamp to last line
            return rangeOfLine(max(1, lineCount(of: text)), in: text)
        }
        var end = start
        while end < ns.length {
            let c = ns.character(at: end)
            end += 1
            if c == 10 { break }
            if c == 13 {
                if end < ns.length, ns.character(at: end) == 10 { end += 1 }
                break
            }
        }
        return NSRange(location: start, length: end - start)
    }

    public static func contentRangeOfLine(_ line: Int, in text: String) -> NSRange {
        let full = rangeOfLine(line, in: text)
        let ns = text as NSString
        if full.length == 0 { return full }
        var length = full.length
        let last = ns.character(at: full.location + length - 1)
        if last == 10 {
            length -= 1
            if length > 0, ns.character(at: full.location + length - 1) == 13 {
                length -= 1
            }
        } else if last == 13 {
            length -= 1
        }
        return NSRange(location: full.location, length: max(0, length))
    }

    public static func offset(line: Int, column: Int, in text: String) -> Int {
        let lineRange = contentRangeOfLine(line, in: text)
        let col = max(1, column)
        return lineRange.location + min(col - 1, lineRange.length)
    }

    public static func duplicateLine(at location: Int, in text: String) -> (text: String, newSelection: NSRange) {
        let line = lineNumber(at: location, in: text)
        let range = rangeOfLine(line, in: text)
        let ns = text as NSString
        let chunk = ns.substring(with: range)
        let insertAt = range.location + range.length
        let mutable = NSMutableString(string: text)
        // If line has no trailing newline (last line), add one before duplicate
        if !chunk.hasSuffix("\n") && !chunk.hasSuffix("\r") {
            mutable.insert("\n" + chunk, at: insertAt)
            let newLoc = insertAt + 1
            return (mutable as String, NSRange(location: newLoc, length: 0))
        } else {
            mutable.insert(chunk, at: insertAt)
            return (mutable as String, NSRange(location: insertAt, length: 0))
        }
    }

    public static func moveLine(at location: Int, in text: String, down: Bool) -> (text: String, newSelection: NSRange)? {
        let line = lineNumber(at: location, in: text)
        let total = lineCount(of: text)
        // A trailing newline creates a phantom empty last line; the last real line is one before it.
        // Note: use NSString hasSuffix — Swift's String.hasSuffix treats "\r\n" as one grapheme.
        let nsText = text as NSString
        let hasTrailingEOL = nsText.hasSuffix("\n") || nsText.hasSuffix("\r")
        let lastRealLine = hasTrailingEOL ? max(1, total - 1) : total
        if down, line >= lastRealLine { return nil }
        if !down, line <= 1 { return nil }

        let a = down ? line : line - 1
        let b = down ? line + 1 : line
        let rangeA = rangeOfLine(a, in: text)
        let rangeB = rangeOfLine(b, in: text)
        let ns = text as NSString
        let lineA = ns.substring(with: rangeA)
        let lineB = ns.substring(with: rangeB)
        let combined = NSRange(location: rangeA.location, length: (rangeB.location + rangeB.length) - rangeA.location)
        let combinedText = ns.substring(with: combined)
        let eol = combinedText.contains("\r\n") ? "\r\n" : (combinedText.contains("\r") ? "\r" : "\n")
        let hadTrailingEOL = combinedText.hasSuffix("\r\n") || combinedText.hasSuffix("\n") || combinedText.hasSuffix("\r")

        // Keep exactly one EOL between the swapped chunks and preserve whether
        // the combined region ended with an EOL (last line without newline stays without one).
        let swapped = stripTrailingEOL(lineB) + eol + stripTrailingEOL(lineA) + (hadTrailingEOL ? eol : "")

        let mutable = NSMutableString(string: text)
        mutable.replaceCharacters(in: combined, with: swapped)
        let newLine = down ? line + 1 : line - 1
        let newOffset = offset(line: newLine, column: 1, in: mutable as String)
        return (mutable as String, NSRange(location: newOffset, length: 0))
    }

    private static func stripTrailingEOL(_ line: String) -> String {
        let ns = line as NSString
        if ns.hasSuffix("\r\n") { return ns.substring(to: ns.length - 2) }
        if ns.hasSuffix("\n") || ns.hasSuffix("\r") { return ns.substring(to: ns.length - 1) }
        return line
    }

    public static func deleteLines(from startLine: Int, through endLine: Int, in text: String) -> String {
        let lo = min(startLine, endLine)
        let hi = max(startLine, endLine)
        let start = rangeOfLine(lo, in: text).location
        let endRange = rangeOfLine(hi, in: text)
        let end = endRange.location + endRange.length
        let mutable = NSMutableString(string: text)
        mutable.deleteCharacters(in: NSRange(location: start, length: end - start))
        return mutable as String
    }
}

/// Rectangular selection described in 1-based line/column.
public struct ColumnSelection: Equatable {
    public var startLine: Int
    public var endLine: Int
    public var startColumn: Int
    public var endColumn: Int

    public init(startLine: Int, endLine: Int, startColumn: Int, endColumn: Int) {
        self.startLine = startLine
        self.endLine = endLine
        self.startColumn = startColumn
        self.endColumn = endColumn
    }

    public var ordered: ColumnSelection {
        let top = min(startLine, endLine)
        let bottom = max(startLine, endLine)
        let left = min(startColumn, endColumn)
        let right = max(startColumn, endColumn)
        return ColumnSelection(startLine: top, endLine: bottom, startColumn: left, endColumn: right)
    }

    public static func from(selection: NSRange, in text: String) -> ColumnSelection {
        let start = selection.location
        let end = selection.location + selection.length
        return ColumnSelection(
            startLine: TextGeometry.lineNumber(at: start, in: text),
            endLine: TextGeometry.lineNumber(at: end, in: text),
            startColumn: TextGeometry.column(at: start, in: text),
            endColumn: TextGeometry.column(at: end, in: text)
        )
    }
}

public enum ColumnEdit {
    public static func insert(_ string: String, selection: ColumnSelection, in text: String) -> String {
        let box = selection.ordered
        let mutable = NSMutableString(string: text)
        for line in (box.startLine...box.endLine).reversed() {
            let offset = TextGeometry.offset(line: line, column: box.startColumn, in: mutable as String)
            mutable.insert(string, at: offset)
        }
        return mutable as String
    }

    public static func delete(selection: ColumnSelection, in text: String) -> String {
        let box = selection.ordered
        let mutable = NSMutableString(string: text)
        for line in (box.startLine...box.endLine).reversed() {
            let content = TextGeometry.contentRangeOfLine(line, in: mutable as String)
            let startCol = box.startColumn - 1
            let endCol = box.endColumn - 1
            guard startCol < content.length else { continue }
            let loc = content.location + startCol
            let len = max(0, min(endCol, content.length) - startCol)
            if len > 0 {
                mutable.deleteCharacters(in: NSRange(location: loc, length: len))
            }
        }
        return mutable as String
    }

    public static func extract(selection: ColumnSelection, in text: String) -> String {
        let box = selection.ordered
        var lines: [String] = []
        let ns = text as NSString
        for line in box.startLine...box.endLine {
            let content = TextGeometry.contentRangeOfLine(line, in: text)
            let startCol = box.startColumn - 1
            let endCol = box.endColumn - 1
            if startCol >= content.length {
                lines.append("")
                continue
            }
            let loc = content.location + startCol
            let len = max(0, min(endCol, content.length) - startCol)
            lines.append(ns.substring(with: NSRange(location: loc, length: len)))
        }
        return lines.joined(separator: "\n")
    }
}
