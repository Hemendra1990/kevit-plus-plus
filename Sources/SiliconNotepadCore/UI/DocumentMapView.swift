import AppKit

protocol DocumentMapViewDelegate: AnyObject {
    func documentMap(_ map: DocumentMapView, didRequestLine line: Int)
}

final class DocumentMapView: NSView {
    weak var delegate: DocumentMapViewDelegate?

    private var text: String = ""
    private var visibleLineRange: ClosedRange<Int> = 1...1
    private var totalLines: Int = 1
    private var bookmarks: Set<Int> = []

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let click = NSClickGestureRecognizer(target: self, action: #selector(clicked(_:)))
        addGestureRecognizer(click)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func applyTheme(_ theme: EditorTheme) {
        layer?.backgroundColor = theme.gutterBackground.cgColor
        needsDisplay = true
    }

    func update(text: String, visibleLines: ClosedRange<Int>, bookmarks: Set<Int>) {
        self.text = text
        self.totalLines = max(1, TextGeometry.lineCount(of: text))
        self.visibleLineRange = visibleLines
        self.bookmarks = bookmarks
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let theme = ThemeManager.shared.current
        theme.gutterBackground.setFill()
        bounds.fill()

        let lineHeight = max(1.0, bounds.height / CGFloat(totalLines))
        // Viewport
        let top = CGFloat(visibleLineRange.lowerBound - 1) * lineHeight
        let height = CGFloat(visibleLineRange.count) * lineHeight
        theme.selection.withAlphaComponent(0.35).setFill()
        NSRect(x: 0, y: top, width: bounds.width, height: max(lineHeight, height)).fill()

        // Sparse line marks (sample)
        theme.foreground.withAlphaComponent(0.25).setFill()
        let step = max(1, totalLines / max(1, Int(bounds.height)))
        for line in stride(from: 1, through: totalLines, by: step) {
            let y = CGFloat(line - 1) * lineHeight
            NSRect(x: 4, y: y, width: bounds.width - 8, height: max(1, lineHeight * 0.6)).fill()
        }

        // Bookmarks
        NSColor.systemOrange.setFill()
        for line in bookmarks {
            let y = CGFloat(line - 1) * lineHeight
            NSBezierPath(ovalIn: NSRect(x: 2, y: y, width: 6, height: 6)).fill()
        }

        theme.gutterForeground.withAlphaComponent(0.4).setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0.5, y: 0))
        path.line(to: NSPoint(x: 0.5, y: bounds.height))
        path.lineWidth = 1
        path.stroke()
    }

    @objc private func clicked(_ gesture: NSClickGestureRecognizer) {
        let y = gesture.location(in: self).y
        let line = min(totalLines, max(1, Int(y / max(bounds.height, 1) * CGFloat(totalLines)) + 1))
        delegate?.documentMap(self, didRequestLine: line)
    }
}
