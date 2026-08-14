import AppKit
import STTextView
import STPluginNeon
import TreeSitterResource

/// Applies Tree-sitter syntax highlighting via STTextView Neon plugin.
@MainActor
enum SyntaxService {
    static func makePlugin(for languageID: String) -> NeonPlugin? {
        guard let language = treeSitterLanguage(for: languageID) else { return nil }
        return NeonPlugin(theme: NeonHighlightTheme.make(), language: language)
    }

    static func treeSitterLanguage(for languageID: String) -> TreeSitterLanguage? {
        guard let name = LanguageRegistry.shared.treeSitterLanguageName(for: languageID) else {
            return nil
        }
        switch name {
        case "bash": return .bash
        case "c": return .c
        case "cpp": return .cpp
        case "csharp": return .csharp
        case "css": return .css
        case "go": return .go
        case "html": return .html
        case "java": return .java
        case "javascript": return .javascript
        case "json": return .json
        case "markdown": return .markdown
        case "php": return .php
        case "python": return .python
        case "ruby": return .ruby
        case "rust": return .rust
        case "swift": return .swift
        case "sql": return .sql
        case "toml": return .toml
        case "typescript": return .typescript
        case "yaml": return .yaml
        default: return nil
        }
    }
}
