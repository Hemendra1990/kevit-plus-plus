import AppKit

final class StatusBarController {
    let view: NSView = {
        let v = NSView()
        v.wantsLayer = true
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private let label = NSTextField(labelWithString: "Ready")
    private let lengthLabel = NSTextField(labelWithString: "")
    private let charLabel = NSTextField(labelWithString: "")

    var line = 1
    var column = 1
    var position = 0
    var length = 0
    var encoding = TextEncodingKind.utf8
    var eol = EOLStyle.lf
    var language = "Plain Text"

    init() {
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        lengthLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        lengthLabel.translatesAutoresizingMaskIntoConstraints = false
        lengthLabel.alignment = .right
        charLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        charLabel.translatesAutoresizingMaskIntoConstraints = false
        charLabel.alignment = .right

        view.addSubview(label)
        view.addSubview(charLabel)
        view.addSubview(lengthLabel)
        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 24),
            label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            charLabel.trailingAnchor.constraint(equalTo: lengthLabel.leadingAnchor, constant: -12),
            charLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            lengthLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            lengthLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            lengthLabel.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12),
            charLabel.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12)
        ])
        applyTheme(ThemeManager.shared.current)
        refresh()
    }

    func applyTheme(_ theme: EditorTheme) {
        view.layer?.backgroundColor = theme.statusBackground.cgColor
        label.textColor = theme.statusForeground
        lengthLabel.textColor = theme.statusForeground
        charLabel.textColor = theme.statusForeground
    }

    func update(
        line: Int,
        column: Int,
        position: Int,
        length: Int,
        encoding: TextEncodingKind,
        eol: EOLStyle,
        language: String,
        columnMode: Bool = false,
        recording: Bool = false,
        bookmarkCount: Int = 0,
        charInfo: String = "",
        zoom: Int = 100,
        selectionLength: Int = 0,
        fileSize: Int64? = nil
    ) {
        self.line = line
        self.column = column
        self.position = position
        self.length = length
        self.encoding = encoding
        self.eol = eol
        self.language = language
        var extras: [String] = []
        if columnMode { extras.append("COL") }
        if recording { extras.append("REC") }
        if bookmarkCount > 0 { extras.append("Bk:\(bookmarkCount)") }
        let suffix = extras.isEmpty ? "" : "    " + extras.joined(separator: "  ")
        label.stringValue = "Ln : \(line)    Col : \(column)    Pos : \(position)    \(encoding.rawValue)    \(eol.shortName)    \(language)\(suffix)    zoom : \(zoom)%"
        charLabel.stringValue = charInfo
        var lengthText = "length : \(length)    sel : \(selectionLength)"
        if let fileSize {
            lengthText += "    size : \(Self.humanSize(fileSize))"
        }
        lengthLabel.stringValue = lengthText
    }

    private static func humanSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func refresh() {
        update(
            line: line,
            column: column,
            position: position,
            length: length,
            encoding: encoding,
            eol: eol,
            language: language
        )
    }
}
