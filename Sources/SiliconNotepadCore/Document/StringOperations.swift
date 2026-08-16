import Foundation

/// User-presentable operation failure (Result requires an Error type).
struct StringOperationError: Error {
    let message: String
}

/// One string operation, described declaratively so the workbench UI builds
/// itself from the cases: adding an operation here (title, category,
/// parameter spec, apply) makes it appear everywhere with no UI changes.
enum StringOperationKind: String, CaseIterable, Equatable {
    // Case & text
    case uppercase
    case lowercase
    case titleCase
    case sentenceCase
    case reverseText
    case trimWhitespace
    case removeExtraSpaces
    // Lines
    case removeBlankLines
    case removeDuplicateLines
    case sortLinesAZ
    case sortLinesZA
    case joinLines
    case splitByDelimiter
    // Search & replace
    case findReplace
    case regexReplace
    case regexExtract
    // Affixes & wrapping
    case addPrefix
    case removePrefix
    case addSuffix
    case removeSuffix
    case addQuotes
    case removeQuotes
    // Line endings
    case lineEndingsLF
    case lineEndingsCRLF
    // Escape / encode
    case escapeCharacters
    case unescapeCharacters
    case base64Encode
    case base64Decode
    case urlEncode
    case urlDecode
    case htmlEscape
    case htmlUnescape
    // Analysis (report-style outputs)
    case countCharacters
    case countWords
    case countLines
    case countSentences

    var title: String {
        switch self {
        case .uppercase: return "UPPERCASE"
        case .lowercase: return "lowercase"
        case .titleCase: return "Title Case"
        case .sentenceCase: return "Sentence case"
        case .reverseText: return "Reverse Text"
        case .trimWhitespace: return "Trim Spaces"
        case .removeExtraSpaces: return "Remove Extra Spaces"
        case .removeBlankLines: return "Remove Blank Lines"
        case .removeDuplicateLines: return "Remove Duplicate Lines"
        case .sortLinesAZ: return "Sort Lines A→Z"
        case .sortLinesZA: return "Sort Lines Z→A"
        case .joinLines: return "Join Lines"
        case .splitByDelimiter: return "Split by Delimiter"
        case .findReplace: return "Find & Replace"
        case .regexReplace: return "Replace with Regex"
        case .regexExtract: return "Extract with Regex"
        case .addPrefix: return "Add Prefix"
        case .removePrefix: return "Remove Prefix"
        case .addSuffix: return "Add Suffix"
        case .removeSuffix: return "Remove Suffix"
        case .addQuotes: return "Add Quotes"
        case .removeQuotes: return "Remove Quotes"
        case .lineEndingsLF: return "Line Endings → LF"
        case .lineEndingsCRLF: return "Line Endings → CRLF"
        case .escapeCharacters: return "Escape Characters"
        case .unescapeCharacters: return "Unescape Characters"
        case .base64Encode: return "Base64 Encode"
        case .base64Decode: return "Base64 Decode"
        case .urlEncode: return "URL Encode"
        case .urlDecode: return "URL Decode"
        case .htmlEscape: return "HTML Escape"
        case .htmlUnescape: return "HTML Unescape"
        case .countCharacters: return "Count Characters"
        case .countWords: return "Count Words"
        case .countLines: return "Count Lines"
        case .countSentences: return "Count Sentences"
        }
    }

    var category: String {
        switch self {
        case .uppercase, .lowercase, .titleCase, .sentenceCase, .reverseText,
             .trimWhitespace, .removeExtraSpaces:
            return "Case & Text"
        case .removeBlankLines, .removeDuplicateLines, .sortLinesAZ, .sortLinesZA,
             .joinLines, .splitByDelimiter:
            return "Lines"
        case .findReplace, .regexReplace, .regexExtract:
            return "Search & Replace"
        case .addPrefix, .removePrefix, .addSuffix, .removeSuffix, .addQuotes, .removeQuotes:
            return "Affixes & Wrapping"
        case .lineEndingsLF, .lineEndingsCRLF:
            return "Line Endings"
        case .escapeCharacters, .unescapeCharacters, .base64Encode, .base64Decode,
             .urlEncode, .urlDecode, .htmlEscape, .htmlUnescape:
            return "Escape & Encode"
        case .countCharacters, .countWords, .countLines, .countSentences:
            return "Analysis"
        }
    }

    /// What the workbench needs to show for this operation.
    enum ParameterSpec: Equatable {
        case none
        case single(label: String, placeholder: String)
        case double(label: String, secondaryLabel: String, placeholder: String, secondaryPlaceholder: String)
        case singleWithFlag(label: String, placeholder: String, flagLabel: String)
        case doubleWithFlag(label: String, secondaryLabel: String, placeholder: String, secondaryPlaceholder: String, flagLabel: String)
        case flagOnly(flagLabel: String)
    }

    var parameterSpec: ParameterSpec {
        switch self {
        case .joinLines:
            return .single(label: "Join with", placeholder: "delimiter (space by default)")
        case .splitByDelimiter:
            return .single(label: "Split on", placeholder: "delimiter")
        case .findReplace:
            return .doubleWithFlag(
                label: "Find", secondaryLabel: "Replace with",
                placeholder: "text", secondaryPlaceholder: "replacement",
                flagLabel: "Case sensitive"
            )
        case .regexReplace:
            return .doubleWithFlag(
                label: "Pattern", secondaryLabel: "Template ($1…)",
                placeholder: "regular expression", secondaryPlaceholder: "replacement",
                flagLabel: "Ignore case"
            )
        case .regexExtract:
            return .singleWithFlag(label: "Pattern", placeholder: "regular expression", flagLabel: "Unique matches only")
        case .addPrefix, .removePrefix:
            return .single(label: "Prefix", placeholder: "text")
        case .addSuffix, .removeSuffix:
            return .single(label: "Suffix", placeholder: "text")
        case .addQuotes, .removeQuotes:
            return .single(label: "Quote character", placeholder: "\"")
        case .countCharacters, .countWords, .countLines, .countSentences,
             .uppercase, .lowercase, .titleCase, .sentenceCase, .reverseText,
             .trimWhitespace, .removeExtraSpaces, .removeBlankLines,
             .removeDuplicateLines, .sortLinesAZ, .sortLinesZA,
             .lineEndingsLF, .lineEndingsCRLF, .escapeCharacters, .unescapeCharacters,
             .base64Encode, .base64Decode, .urlEncode, .urlDecode,
             .htmlEscape, .htmlUnescape:
            return .none
        }
    }

    /// Applies one operation. Failures carry a user-presentable message.
    func apply(
        _ input: String,
        parameter: String = "",
        secondary: String = "",
        flag: Bool = false
    ) -> Result<String, StringOperationError> {
        switch self {
        case .uppercase:
            return .success(input.uppercased())
        case .lowercase:
            return .success(input.lowercased())
        case .titleCase:
            return .success(input.titleCased())
        case .sentenceCase:
            return .success(input.sentenceCased())
        case .reverseText:
            return .success(String(input.reversed()))
        case .trimWhitespace:
            return .success(input.lines().map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n"))
        case .removeExtraSpaces:
            let collapsed = input.lines().map { line -> String in
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                    .flatMap { $0.split(separator: "\t", omittingEmptySubsequences: true) }
                return parts.joined(separator: " ")
            }
            return .success(collapsed.joined(separator: "\n"))
        case .removeBlankLines:
            return .success(TextTransforms.removeBlankLines(input))
        case .removeDuplicateLines:
            var seen = Set<String>()
            let kept = input.lines().filter { seen.insert($0).inserted }
            return .success(kept.joined(separator: "\n"))
        case .sortLinesAZ:
            return .success(TextTransforms.sortLines(input, descending: false, unique: false))
        case .sortLinesZA:
            return .success(TextTransforms.sortLines(input, descending: true, unique: false))
        case .joinLines:
            let delimiter = parameter.isEmpty ? " " : parameter
            return .success(input.lines().joined(separator: delimiter))
        case .splitByDelimiter:
            guard !parameter.isEmpty else {
                return .failure(StringOperationError(message: "Enter a delimiter to split on."))
            }
            let parts = input.components(separatedBy: parameter)
            return .success(parts.joined(separator: "\n"))
        case .findReplace:
            guard !parameter.isEmpty else { return .failure(StringOperationError(message: "Enter text to find.")) }
            return .success(input.replacingOccurrences(
                of: parameter,
                with: secondary,
                options: flag ? [] : [.caseInsensitive]
            ))
        case .regexReplace:
            return regexTransform(pattern: parameter, options: flag ? [.caseInsensitive] : []) { regex in
                regex.stringByReplacingMatches(
                    in: input,
                    options: [],
                    range: NSRange(location: 0, length: (input as NSString).length),
                    withTemplate: secondary
                )
            }
        case .regexExtract:
            return regexTransform(pattern: parameter, options: []) { regex in
                let range = NSRange(location: 0, length: (input as NSString).length)
                let matches = regex.matches(in: input, options: [], range: range)
                var extracted = matches.map { match -> String in
                    // Prefer capture group 1 when the pattern defines one.
                    if match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: input) {
                        return String(input[r])
                    }
                    if let r = Range(match.range, in: input) {
                        return String(input[r])
                    }
                    return ""
                }
                if flag {
                    var seen = Set<String>()
                    extracted = extracted.filter { seen.insert($0).inserted }
                }
                return extracted.joined(separator: "\n")
            }
        case .addPrefix:
            return .success(input.lines().map { parameter + $0 }.joined(separator: "\n"))
        case .removePrefix:
            return .success(input.lines().map { line -> String in
                line.hasPrefix(parameter) ? String(line.dropFirst(parameter.count)) : line
            }.joined(separator: "\n"))
        case .addSuffix:
            return .success(input.lines().map { $0 + parameter }.joined(separator: "\n"))
        case .removeSuffix:
            return .success(input.lines().map { line -> String in
                line.hasSuffix(parameter) && !parameter.isEmpty ? String(line.dropLast(parameter.count)) : line
            }.joined(separator: "\n"))
        case .addQuotes:
            let quote = parameter.isEmpty ? "\"" : parameter
            return .success(input.lines().map { quote + $0 + quote }.joined(separator: "\n"))
        case .removeQuotes:
            let quote = parameter.isEmpty ? "\"" : parameter
            return .success(input.lines().map { line -> String in
                var text = line
                if text.hasPrefix(quote) { text = String(text.dropFirst(quote.count)) }
                if text.hasSuffix(quote) && !text.isEmpty { text = String(text.dropLast(quote.count)) }
                return text
            }.joined(separator: "\n"))
        case .lineEndingsLF:
            return .success(EncodingDetector.normalizeEOL(input, to: .lf))
        case .lineEndingsCRLF:
            return .success(EncodingDetector.normalizeEOL(input, to: .crlf))
        case .escapeCharacters:
            var escaped = ""
            input.unicodeScalars.forEach { scalar in
                switch scalar {
                case "\\": escaped += "\\\\"
                case "\"": escaped += "\\\""
                case "\n": escaped += "\\n"
                case "\r": escaped += "\\r"
                case "\t": escaped += "\\t"
                default: escaped.unicodeScalars.append(scalar)
                }
            }
            return .success(escaped)
        case .unescapeCharacters:
            var out = ""
            var iterator = input.unicodeScalars.makeIterator()
            while let scalar = iterator.next() {
                guard scalar == "\\" else {
                    out.unicodeScalars.append(scalar)
                    continue
                }
                switch iterator.next() {
                case "n"? : out += "\n"
                case "r"? : out += "\r"
                case "t"? : out += "\t"
                case "\\"? : out += "\\"
                case "\""?: out += "\""
                case nil: out += "\\"
                case .some(let other): out.unicodeScalars.append(other)
                }
            }
            return .success(out)
        case .base64Encode:
            return .success(Data(input.utf8).base64EncodedString())
        case .base64Decode:
            let cleaned = parameter.isEmpty
                ? input.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: " ", with: "")
                : input
            guard let data = Data(base64Encoded: cleaned),
                  let decoded = String(data: data, encoding: .utf8) else {
                return .failure(StringOperationError(message: "Not valid Base64."))
            }
            return .success(decoded)
        case .urlEncode:
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            guard let encoded = input.addingPercentEncoding(withAllowedCharacters: allowed) else {
                return .failure(StringOperationError(message: "Could not URL-encode this text."))
            }
            return .success(encoded)
        case .urlDecode:
            guard let decoded = input.removingPercentEncoding else {
                return .failure(StringOperationError(message: "Not valid URL encoding."))
            }
            return .success(decoded)
        case .htmlEscape:
            return .success(input
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;"))
        case .htmlUnescape:
            return .success(input
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&apos;", with: "'")
                .replacingOccurrences(of: "&nbsp;", with: " "))
        case .countCharacters:
            let chars = input.unicodeScalars.count
            let graphemes = input.count
            return .success("Characters (grapheme clusters): \(graphemes)\nUnicode scalars: \(chars)\nBytes (UTF-8): \(input.utf8.count)")
        case .countWords:
            return .success("Words: \(input.words().count)")
        case .countLines:
            let lines = input.lines()
            let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
            return .success("Lines: \(lines.count)\nNon-empty lines: \(nonEmpty)")
        case .countSentences:
            return .success("Sentences: \(input.sentenceCount())")
        }
    }

    private func regexTransform(
        pattern: String,
        options: NSRegularExpression.Options,
        transform: (NSRegularExpression) -> String
    ) -> Result<String, StringOperationError> {
        guard !pattern.isEmpty else { return .failure(StringOperationError(message: "Enter a regular expression.")) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return .failure(StringOperationError(message: "Invalid regular expression."))
        }
        return .success(transform(regex))
    }
}

// MARK: - Chain

/// A configured operation inside a chain.
struct StringChainStep: Equatable {
    var kind: StringOperationKind
    var parameter: String = ""
    var secondary: String = ""
    var flag: Bool = false

    var defaultFlag: Bool {
        // Case sensitivity reads better checked by default.
        kind == .findReplace
    }

    /// Compact description for the chain list, e.g. `Find & Replace — "a" → "b"`.
    var summary: String {
        switch kind.parameterSpec {
        case .none:
            return kind.title
        case .single:
            return "\(kind.title) — \(parameter.isEmpty ? "…" : parameter)"
        case .singleWithFlag:
            return "\(kind.title) — \(parameter.isEmpty ? "…" : parameter)"
        case .double, .doubleWithFlag:
            return "\(kind.title) — \(parameter.isEmpty ? "…" : parameter) → \(secondary.isEmpty ? "…" : secondary)"
        case .flagOnly:
            return kind.title
        }
    }
}

/// Ordered pipeline of operations with reordering/removal helpers.
struct StringOperationChain: Equatable {
    var steps: [StringChainStep] = []

    var isEmpty: Bool { steps.isEmpty }

    mutating func append(_ step: StringChainStep) {
        steps.append(step)
    }

    mutating func remove(at index: Int) {
        guard steps.indices.contains(index) else { return }
        steps.remove(at: index)
    }

    mutating func move(from index: Int, to destination: Int) {
        guard steps.indices.contains(index) else { return }
        let clamped = max(0, min(destination, steps.count - 1))
        let step = steps.remove(at: index)
        steps.insert(step, at: clamped)
    }

    /// Runs the pipeline; the first failing step names itself in the message.
    func evaluate(_ input: String) -> Result<String, StringOperationError> {
        var current = input
        for (index, step) in steps.enumerated() {
            switch step.kind.apply(current, parameter: step.parameter, secondary: step.secondary, flag: step.flag) {
            case .success(let output):
                current = output
            case .failure(let message):
                return .failure(StringOperationError(message: "Step \(index + 1) — \(step.kind.title): \(message)"))
            }
        }
        return .success(current)
    }
}

// MARK: - Text helpers

private extension String {
    func lines() -> [String] {
        // NSString split so CRLF tails don't leave phantom \r on lines.
        (self as NSString).components(separatedBy: "\n").map {
            $0.hasSuffix("\r") ? String($0.dropLast()) : $0
        }
    }

    func words() -> [String] {
        split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map(String.init)
    }

    func titleCased() -> String {
        let lower = lowercased()
        var result = ""
        var capitalizeNext = true
        for ch in lower {
            if ch.isWhitespace {
                capitalizeNext = true
                result.append(ch)
            } else if capitalizeNext {
                result.append(contentsOf: String(ch).uppercased())
                capitalizeNext = false
            } else {
                result.append(ch)
            }
        }
        return result
    }

    func sentenceCased() -> String {
        let lower = lowercased()
        var result = ""
        var capitalizeNext = true
        for ch in lower {
            if ch == "." || ch == "!" || ch == "?" || ch == "\n" {
                capitalizeNext = true
                result.append(ch)
            } else if capitalizeNext && !ch.isWhitespace {
                result.append(contentsOf: String(ch).uppercased())
                capitalizeNext = false
            } else {
                result.append(ch)
            }
        }
        return result
    }

    func sentenceCount() -> Int {
        var count = 0
        var inSentence = false
        for ch in self {
            if ch == "." || ch == "!" || ch == "?" {
                if inSentence { count += 1 }
                inSentence = false
            } else if !ch.isWhitespace && !ch.isNewline {
                inSentence = true
            }
        }
        if inSentence { count += 1 }
        return count
    }
}
