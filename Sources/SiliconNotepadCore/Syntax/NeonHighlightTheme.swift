import AppKit
import STPluginNeon

/// Neon `Theme.default` loads colors from xcassets via `NSColor(named:bundle:)`.
/// SwiftPM copies the catalog uncompiled, so that force-unwrap crashes on first highlight.
enum NeonHighlightTheme {
    static func make(dark: Bool = ThemeManager.shared.current.isDark) -> Theme {
        func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
            NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
        }

        let colors: [String: NSColor]
        if dark {
            colors = [
                "plain": rgb(255, 255, 255),
                "boolean": rgb(100, 220, 108),
                "comment": rgb(127, 140, 141),
                "constructor": rgb(100, 220, 108),
                "function.call": rgb(244, 176, 134),
                "include": rgb(100, 220, 108),
                "keyword": rgb(100, 220, 108),
                "keyword.function": rgb(205, 146, 139),
                "keyword.return": rgb(100, 220, 108),
                "method": rgb(205, 146, 139),
                "number": rgb(227, 255, 48),
                "operator": rgb(255, 255, 255),
                "parameter": rgb(255, 255, 255),
                "punctuation.special": rgb(255, 255, 255),
                "string": rgb(230, 126, 34),
                "text.literal": rgb(230, 126, 34),
                "text.title": rgb(241, 196, 15),
                "type": rgb(52, 152, 219),
                "variable.builtin": rgb(155, 89, 182),
                "variable": rgb(236, 240, 241)
            ]
        } else {
            colors = [
                "plain": rgb(0, 0, 0),
                "boolean": rgb(155, 35, 147),
                "comment": rgb(0, 128, 0),
                "constructor": rgb(155, 35, 147),
                "function.call": rgb(11, 79, 121),
                "include": rgb(155, 35, 147),
                "keyword": rgb(155, 35, 147),
                "keyword.function": rgb(50, 109, 116),
                "keyword.return": rgb(155, 35, 147),
                "method": rgb(50, 109, 116),
                "number": rgb(28, 0, 207),
                "operator": rgb(0, 0, 0),
                "parameter": rgb(0, 0, 0),
                "punctuation.special": rgb(0, 0, 0),
                "string": rgb(163, 21, 21),
                "text.literal": rgb(163, 21, 21),
                "text.title": rgb(0, 0, 128),
                "type": rgb(43, 145, 175),
                "variable.builtin": rgb(155, 35, 147),
                "variable": rgb(0, 0, 0)
            ]
        }

        let mediumTokens: Set<String> = ["constructor", "keyword", "keyword.function", "keyword.return", "text.title"]
        let fonts = Dictionary(uniqueKeysWithValues: colors.keys.map { token in
            let weight: NSFont.Weight = mediumTokens.contains(token) ? .medium : .regular
            return (token, NSFont.monospacedSystemFont(ofSize: 0, weight: weight))
        })
        return Theme(colors: Theme.Colors(colors: colors), fonts: Theme.Fonts(fonts: fonts))
    }
}
