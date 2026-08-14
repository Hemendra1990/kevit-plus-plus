import AppKit

extension Notification.Name {
    static let themeDidChange = Notification.Name("KevitPlusPlus.themeDidChange")
    static let preferencesDidChange = Notification.Name("KevitPlusPlus.preferencesDidChange")
}

struct EditorTheme {
    let name: String
    let isDark: Bool
    let background: NSColor
    let foreground: NSColor
    let gutterBackground: NSColor
    let gutterForeground: NSColor
    let gutterSeparator: NSColor
    let lineHighlight: NSColor
    let selection: NSColor
    let statusBackground: NSColor
    let statusForeground: NSColor
    let chromeBackground: NSColor
    let tabBackground: NSColor
    let tabActiveBackground: NSColor
    let tabInactiveText: NSColor
    let tabActiveText: NSColor
    let tabAccent: NSColor
    let findBackground: NSColor
    let toolbarBackground: NSColor

    /// Classic Notepad++ light chrome (grey tabs, white active, orange accents).
    static let light = EditorTheme(
        name: "Notepad++ Light",
        isDark: false,
        background: NSColor(calibratedWhite: 1.0, alpha: 1),
        foreground: NSColor(calibratedWhite: 0.05, alpha: 1),
        gutterBackground: NSColor(calibratedRed: 0.93, green: 0.93, blue: 0.93, alpha: 1),
        gutterForeground: NSColor(calibratedWhite: 0.45, alpha: 1),
        gutterSeparator: NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.15, alpha: 1),
        lineHighlight: NSColor(calibratedRed: 1.0, green: 0.97, blue: 0.90, alpha: 1),
        selection: NSColor(calibratedRed: 0.75, green: 0.86, blue: 1.0, alpha: 1),
        statusBackground: NSColor(calibratedRed: 0.90, green: 0.90, blue: 0.90, alpha: 1),
        statusForeground: NSColor(calibratedWhite: 0.15, alpha: 1),
        chromeBackground: NSColor(calibratedRed: 0.94, green: 0.94, blue: 0.94, alpha: 1),
        tabBackground: NSColor(calibratedRed: 0.88, green: 0.88, blue: 0.88, alpha: 1),
        tabActiveBackground: NSColor(calibratedWhite: 1.0, alpha: 1),
        tabInactiveText: NSColor(calibratedWhite: 0.35, alpha: 1),
        tabActiveText: NSColor(calibratedWhite: 0.05, alpha: 1),
        tabAccent: NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.15, alpha: 1),
        findBackground: NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.96, alpha: 1),
        toolbarBackground: NSColor(calibratedRed: 0.96, green: 0.96, blue: 0.96, alpha: 1)
    )

    static let dark = EditorTheme(
        name: "Notepad++ Dark",
        isDark: true,
        background: NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.18, alpha: 1),
        foreground: NSColor(calibratedWhite: 0.90, alpha: 1),
        gutterBackground: NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.14, alpha: 1),
        gutterForeground: NSColor(calibratedWhite: 0.50, alpha: 1),
        gutterSeparator: NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.15, alpha: 1),
        lineHighlight: NSColor(calibratedRed: 0.22, green: 0.23, blue: 0.25, alpha: 1),
        selection: NSColor(calibratedRed: 0.25, green: 0.40, blue: 0.60, alpha: 1),
        statusBackground: NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.12, alpha: 1),
        statusForeground: NSColor(calibratedWhite: 0.75, alpha: 1),
        chromeBackground: NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.16, alpha: 1),
        tabBackground: NSColor(calibratedRed: 0.18, green: 0.19, blue: 0.20, alpha: 1),
        tabActiveBackground: NSColor(calibratedRed: 0.22, green: 0.23, blue: 0.25, alpha: 1),
        tabInactiveText: NSColor(calibratedWhite: 0.55, alpha: 1),
        tabActiveText: NSColor(calibratedWhite: 0.95, alpha: 1),
        tabAccent: NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.15, alpha: 1),
        findBackground: NSColor(calibratedRed: 0.18, green: 0.19, blue: 0.20, alpha: 1),
        toolbarBackground: NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.18, alpha: 1)
    )
}

final class ThemeManager {
    static let shared = ThemeManager()

    private let themeKey = "theme.isDark"

    var isDark: Bool {
        didSet {
            UserDefaults.standard.set(isDark, forKey: themeKey)
            NotificationCenter.default.post(name: .themeDidChange, object: current)
        }
    }

    var current: EditorTheme {
        isDark ? .dark : .light
    }

    private init() {
        // Default to classic Notepad++ light look.
        if UserDefaults.standard.object(forKey: themeKey) == nil {
            isDark = false
        } else {
            isDark = UserDefaults.standard.bool(forKey: themeKey)
        }
    }

    func toggle() { isDark.toggle() }
    func setDark(_ dark: Bool) { isDark = dark }
}
