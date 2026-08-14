import AppKit
import Foundation

final class Preferences {
    static let shared = Preferences()

    private enum Keys {
        static let fontSize = "prefs.fontSize"
        static let tabWidth = "prefs.tabWidth"
        static let wordWrap = "prefs.wordWrap"
        static let showLineNumbers = "prefs.showLineNumbers"
        static let defaultEncoding = "prefs.defaultEncoding"
        static let defaultEOL = "prefs.defaultEOL"
        static let autoReload = "prefs.autoReload"
        static let showToolbar = "prefs.showToolbar"
    }

    var fontSize: CGFloat {
        get {
            let value = UserDefaults.standard.double(forKey: Keys.fontSize)
            return value > 0 ? CGFloat(value) : 13
        }
        set {
            UserDefaults.standard.set(Double(newValue), forKey: Keys.fontSize)
            notify()
        }
    }

    var tabWidth: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: Keys.tabWidth)
            return value > 0 ? value : 4
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.tabWidth)
            notify()
        }
    }

    var wordWrap: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.wordWrap) == nil { return false }
            return UserDefaults.standard.bool(forKey: Keys.wordWrap)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.wordWrap)
            notify()
        }
    }

    var showLineNumbers: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.showLineNumbers) == nil { return true }
            return UserDefaults.standard.bool(forKey: Keys.showLineNumbers)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.showLineNumbers)
            notify()
        }
    }

    var defaultEncoding: TextEncodingKind {
        get {
            let raw = UserDefaults.standard.string(forKey: Keys.defaultEncoding) ?? TextEncodingKind.utf8.rawValue
            return TextEncodingKind(rawValue: raw) ?? .utf8
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.defaultEncoding)
            notify()
        }
    }

    var defaultEOL: EOLStyle {
        get {
            let raw = UserDefaults.standard.string(forKey: Keys.defaultEOL) ?? EOLStyle.lf.rawValue
            return EOLStyle(rawValue: raw) ?? .lf
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.defaultEOL)
            notify()
        }
    }

    var autoReloadFiles: Bool {
        get {
            if UserDefaults.standard.object(forKey: Keys.autoReload) == nil { return true }
            return UserDefaults.standard.bool(forKey: Keys.autoReload)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.autoReload)
            notify()
        }
    }

    var showToolbar: Bool {
        get {
            // Classic N++ strip is default; macOS NSToolbar opt-in.
            if UserDefaults.standard.object(forKey: Keys.showToolbar) == nil { return false }
            return UserDefaults.standard.bool(forKey: Keys.showToolbar)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.showToolbar)
            notify()
        }
    }

    var editorFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    private init() {}

    private func notify() {
        NotificationCenter.default.post(name: .preferencesDidChange, object: self)
    }
}
