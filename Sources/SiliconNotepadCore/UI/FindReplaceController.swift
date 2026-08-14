import AppKit

protocol FindReplaceControllerDelegate: AnyObject {
    func findReplaceFindNext(_ controller: FindReplaceController)
    func findReplaceFindPrevious(_ controller: FindReplaceController)
    func findReplaceReplace(_ controller: FindReplaceController)
    func findReplaceReplaceAll(_ controller: FindReplaceController)
    func findReplaceQueryDidChange(_ controller: FindReplaceController)
}

final class FindReplaceController: NSObject {
    weak var delegate: FindReplaceControllerDelegate?

    let view: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let findField = NSTextField(string: "")
    private let replaceField = NSTextField(string: "")
    private let caseButton = NSButton(checkboxWithTitle: "Match case", target: nil, action: nil)
    private let wordButton = NSButton(checkboxWithTitle: "Whole word", target: nil, action: nil)
    private let regexButton = NSButton(checkboxWithTitle: "Regular expression", target: nil, action: nil)
    private let wrapButton = NSButton(checkboxWithTitle: "Wrap around", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    var findString: String { findField.stringValue }
    var replaceString: String { replaceField.stringValue }
    var matchCase: Bool { caseButton.state == .on }
    var wholeWord: Bool { wordButton.state == .on }
    var useRegex: Bool { regexButton.state == .on }
    var wrapAround: Bool { wrapButton.state == .on }

    private(set) var isVisible = false

    override init() {
        super.init()
        wrapButton.state = .on
        findField.placeholderString = "Find"
        replaceField.placeholderString = "Replace"
        findField.delegate = self
        statusLabel.font = .systemFont(ofSize: 11)

        let findNext = NSButton(title: "Find Next", target: self, action: #selector(findNext))
        let findPrev = NSButton(title: "Find Previous", target: self, action: #selector(findPrevious))
        let replace = NSButton(title: "Replace", target: self, action: #selector(replace))
        let replaceAll = NSButton(title: "Replace All", target: self, action: #selector(replaceAll))
        let close = NSButton(title: "Done", target: self, action: #selector(hide))

        for button in [findNext, findPrev, replace, replaceAll, close] {
            button.bezelStyle = .rounded
        }

        let options = NSStackView(views: [caseButton, wordButton, regexButton, wrapButton])
        options.orientation = .horizontal
        options.spacing = 12

        let row1 = NSStackView(views: [labeled("Find:", findField), findNext, findPrev, close])
        row1.orientation = .horizontal
        row1.spacing = 8

        let row2 = NSStackView(views: [labeled("Replace:", replaceField), replace, replaceAll, statusLabel])
        row2.orientation = .horizontal
        row2.spacing = 8

        let stack = NSStackView(views: [row1, row2, options])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            findField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220),
            replaceField.widthAnchor.constraint(greaterThanOrEqualToConstant: 220)
        ])

        view.isHidden = true
        applyTheme(ThemeManager.shared.current)
    }

    func applyTheme(_ theme: EditorTheme) {
        view.layer?.backgroundColor = theme.findBackground.cgColor
        statusLabel.textColor = theme.statusForeground
    }

    func show(focusReplace: Bool = false) {
        view.isHidden = false
        isVisible = true
        if focusReplace {
            view.window?.makeFirstResponder(replaceField)
        } else {
            view.window?.makeFirstResponder(findField)
        }
    }

    @objc func hide() {
        view.isHidden = true
        isVisible = false
    }

    func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    func setFindString(_ string: String) {
        findField.stringValue = string
    }

    private func labeled(_ title: String, _ field: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 12)
        let box = NSStackView(views: [label, field])
        box.orientation = .horizontal
        box.spacing = 6
        return box
    }

    @objc private func findNext() { delegate?.findReplaceFindNext(self) }
    @objc private func findPrevious() { delegate?.findReplaceFindPrevious(self) }
    @objc private func replace() { delegate?.findReplaceReplace(self) }
    @objc private func replaceAll() { delegate?.findReplaceReplaceAll(self) }
}

extension FindReplaceController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        delegate?.findReplaceQueryDidChange(self)
    }
}

public struct FindMatchEngine {
    public let find: String
    public let matchCase: Bool
    public let wholeWord: Bool
    public let useRegex: Bool

    public init(find: String, matchCase: Bool, wholeWord: Bool, useRegex: Bool) {
        self.find = find
        self.matchCase = matchCase
        self.wholeWord = wholeWord
        self.useRegex = useRegex
    }

    public func firstMatch(in text: String, from location: Int, forward: Bool) -> Range<String.Index>? {
        guard !find.isEmpty else { return nil }
        if useRegex {
            return regexMatch(in: text, from: location, forward: forward)
        }
        return plainMatch(in: text, from: location, forward: forward)
    }

    public func allMatches(in text: String) -> [Range<String.Index>] {
        var results: [Range<String.Index>] = []
        var cursor = 0
        while let match = firstMatch(in: text, from: cursor, forward: true) {
            results.append(match)
            let next = match.upperBound.utf16Offset(in: text)
            if next <= cursor { break }
            cursor = next
        }
        return results
    }

    /// Compiles the regex and reports the error, or nil if the pattern is valid (or plain-text mode).
    public func regexError() -> String? {
        guard useRegex else { return nil }
        do {
            _ = try compiledRegex()
            return nil
        } catch {
            return (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String ?? error.localizedDescription
        }
    }

    /// Replacement string honoring regex backreferences ($1, ${name}, …). Plain text mode returns the template unchanged.
    public func replacementString(in text: String, match: Range<String.Index>, template: String) -> String? {
        guard useRegex else { return template }
        guard let regex = try? compiledRegex() else { return nil }
        let nsRange = NSRange(match, in: text)
        let full = NSRange(location: 0, length: (text as NSString).length)
        guard let result = regex.matches(in: text, range: full).first(where: { $0.range == nsRange }) else {
            return nil
        }
        return regex.replacementString(for: result, in: text, offset: 0, template: template)
    }

    private func compiledRegex() throws -> NSRegularExpression {
        var options: NSRegularExpression.Options = []
        if !matchCase { options.insert(.caseInsensitive) }
        let pattern = wholeWord ? "\\b(?:\(find))\\b" : find
        return try NSRegularExpression(pattern: pattern, options: options)
    }

    private func plainMatch(in text: String, from location: Int, forward: Bool) -> Range<String.Index>? {
        let options: String.CompareOptions = matchCase ? [] : [.caseInsensitive]
        // `location` is a UTF-16 offset (NSTextView units) — convert without Character-counting.
        let clamped = min(max(location, 0), text.utf16.count)
        let start = String.Index(utf16Offset: clamped, in: text)

        if forward {
            let searchRange = start..<text.endIndex
            guard let range = text.range(of: find, options: options, range: searchRange) else { return nil }
            return wholeWord ? (isWholeWord(range, in: text) ? range : continuePlain(text, after: range, forward: true)) : range
        } else {
            let searchRange = text.startIndex..<start
            guard let range = text.range(of: find, options: options.union(.backwards), range: searchRange) else { return nil }
            return wholeWord ? (isWholeWord(range, in: text) ? range : continuePlain(text, after: range, forward: false)) : range
        }
    }

    private func continuePlain(_ text: String, after range: Range<String.Index>, forward: Bool) -> Range<String.Index>? {
        let loc = forward
            ? range.upperBound.utf16Offset(in: text)
            : range.lowerBound.utf16Offset(in: text)
        return firstMatch(in: text, from: loc, forward: forward)
    }

    private func isWholeWord(_ range: Range<String.Index>, in text: String) -> Bool {
        let wordChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if range.lowerBound > text.startIndex {
            let prev = text[text.index(before: range.lowerBound)]
            if prev.unicodeScalars.contains(where: { wordChars.contains($0) }) { return false }
        }
        if range.upperBound < text.endIndex {
            let next = text[range.upperBound]
            if next.unicodeScalars.contains(where: { wordChars.contains($0) }) { return false }
        }
        return true
    }

    private func regexMatch(in text: String, from location: Int, forward: Bool) -> Range<String.Index>? {
        guard let regex = try? compiledRegex() else { return nil }
        let nsText = text as NSString
        let full = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, options: [], range: full)
        guard !matches.isEmpty else { return nil }

        if forward {
            for match in matches {
                if match.range.location >= location,
                   let range = Range(match.range, in: text) {
                    return range
                }
            }
        } else {
            for match in matches.reversed() {
                if match.range.location < location,
                   let range = Range(match.range, in: text) {
                    return range
                }
            }
        }
        return nil
    }
}
