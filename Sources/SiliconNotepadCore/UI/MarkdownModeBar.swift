import AppKit

/// Slim toolbar row shown above the editor while a Markdown (or
/// Markdown-detected) document is active: mode switcher on the trailing
/// edge, detection badge on the leading edge. Reusable wherever a
/// Markdown-capable editing surface appears.
final class MarkdownModeBar: NSView {
    var onModeChange: ((MarkdownViewMode) -> Void)?
    var onToggleFullscreen: (() -> Void)?

    private let segmented = NSSegmentedControl()
    private let fullscreenButton = NSButton()
    private let badgeIcon = NSImageView()
    private let badgeLabel = NSTextField(labelWithString: "Markdown")

    private(set) var mode: MarkdownViewMode = .split
    private(set) var isFullscreen = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        segmented.segmentStyle = .texturedRounded
        segmented.segmentCount = 3
        segmented.trackingMode = .selectOne
        segmented.target = self
        segmented.action = #selector(segmentedChanged(_:))
        for (index, item) in MarkdownViewMode.allCases.enumerated() {
            segmented.setLabel(item.label, forSegment: index)
        }
        // NSSegmentedControl has no per-segment tooltips on macOS.
        segmented.toolTip = "View mode: Code (⌥⌘1) · Split (⌥⌘2) · Preview (⌥⌘3)"
        segmented.setSelected(true, forSegment: 1)
        segmented.translatesAutoresizingMaskIntoConstraints = false

        fullscreenButton.bezelStyle = .texturedRounded
        fullscreenButton.isBordered = true
        fullscreenButton.toolTip = "Fullscreen Preview (⌥⌘F — Esc to exit)"
        fullscreenButton.image = NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Fullscreen Preview")
        fullscreenButton.imagePosition = .imageOnly
        fullscreenButton.target = self
        fullscreenButton.action = #selector(fullscreenClicked(_:))
        fullscreenButton.translatesAutoresizingMaskIntoConstraints = false

        badgeIcon.image = NSImage(systemSymbolName: "text.badge.checkmark", accessibilityDescription: "Markdown detected")
        badgeIcon.contentTintColor = .systemGreen
        badgeIcon.translatesAutoresizingMaskIntoConstraints = false

        badgeLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        badgeLabel.textColor = .secondaryLabelColor
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(badgeIcon)
        addSubview(badgeLabel)
        addSubview(fullscreenButton)
        addSubview(segmented)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),

            badgeIcon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            badgeIcon.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeLabel.leadingAnchor.constraint(equalTo: badgeIcon.trailingAnchor, constant: 4),
            badgeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            fullscreenButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            fullscreenButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            segmented.trailingAnchor.constraint(equalTo: fullscreenButton.leadingAnchor, constant: -8),
            segmented.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - State

    func setMode(_ newMode: MarkdownViewMode, animated: Bool = false) {
        mode = newMode
        if let index = MarkdownViewMode.allCases.firstIndex(of: newMode) {
            segmented.setSelected(true, forSegment: index)
        }
    }

    func setFullscreen(_ active: Bool) {
        isFullscreen = active
        let name = active ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
        fullscreenButton.image = NSImage(systemSymbolName: name, accessibilityDescription: active ? "Exit Fullscreen Preview" : "Fullscreen Preview")
        fullscreenButton.toolTip = active ? "Exit Fullscreen Preview (Esc or ⌥⌘F)" : "Fullscreen Preview (⌥⌘F)"
    }

    /// `confirmed` = recognized by extension/language; otherwise show the
    /// heuristic "detected" wording so users know why it lit up.
    func setBadge(kind: String, confirmed: Bool) {
        badgeLabel.stringValue = confirmed ? kind : "\(kind) (detected)"
    }

    func applyTheme(_ theme: EditorTheme) {
        layer?.backgroundColor = theme.toolbarBackground.cgColor
    }

    // MARK: - Actions

    @objc private func segmentedChanged(_ sender: NSSegmentedControl) {
        let all = MarkdownViewMode.allCases
        if sender.selectedSegment < all.count, sender.selectedSegment >= 0 {
            mode = all[sender.selectedSegment]
            onModeChange?(mode)
        }
    }

    @objc private func fullscreenClicked(_ sender: NSButton) {
        onToggleFullscreen?()
    }
}
