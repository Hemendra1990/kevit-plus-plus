import Foundation

struct LanguageInfo: Hashable {
    let id: String
    let displayName: String
    let extensions: [String]
    let category: String
}

public final class LanguageRegistry {
    public static let shared = LanguageRegistry()

    let languages: [LanguageInfo] = [
        // A
        LanguageInfo(id: "plaintext", displayName: "Normal Text", extensions: ["txt", "text", "log"], category: "A"),
        LanguageInfo(id: "actionscript", displayName: "ActionScript", extensions: ["as"], category: "A"),
        // B
        LanguageInfo(id: "bash", displayName: "Bash / Shell", extensions: ["sh", "bash", "zsh", "command", "ksh"], category: "B"),
        LanguageInfo(id: "batch", displayName: "Batch", extensions: ["bat", "cmd"], category: "B"),
        // C
        LanguageInfo(id: "c", displayName: "C", extensions: ["c", "h"], category: "C"),
        LanguageInfo(id: "cpp", displayName: "C++", extensions: ["cpp", "cc", "cxx", "hpp", "hh", "hxx", "ino"], category: "C"),
        LanguageInfo(id: "csharp", displayName: "C#", extensions: ["cs"], category: "C"),
        LanguageInfo(id: "css", displayName: "CSS", extensions: ["css"], category: "C"),
        LanguageInfo(id: "cmake", displayName: "CMake", extensions: ["cmake"], category: "C"),
        // D
        LanguageInfo(id: "diff", displayName: "Diff", extensions: ["diff", "patch"], category: "D"),
        LanguageInfo(id: "dockerfile", displayName: "Dockerfile", extensions: ["dockerfile"], category: "D"),
        // G
        LanguageInfo(id: "go", displayName: "Go", extensions: ["go"], category: "G"),
        LanguageInfo(id: "graphql", displayName: "GraphQL", extensions: ["graphql", "gql"], category: "G"),
        // H
        LanguageInfo(id: "html", displayName: "HTML", extensions: ["html", "htm", "xhtml", "shtml"], category: "H"),
        // I
        LanguageInfo(id: "ini", displayName: "INI / Config", extensions: ["ini", "cfg", "conf", "properties"], category: "I"),
        // J
        LanguageInfo(id: "java", displayName: "Java", extensions: ["java"], category: "J"),
        LanguageInfo(id: "javascript", displayName: "JavaScript", extensions: ["js", "mjs", "cjs", "jsx"], category: "J"),
        LanguageInfo(id: "json", displayName: "JSON", extensions: ["json", "jsonc"], category: "J"),
        LanguageInfo(id: "julia", displayName: "Julia", extensions: ["jl"], category: "J"),
        // K
        LanguageInfo(id: "kotlin", displayName: "Kotlin", extensions: ["kt", "kts"], category: "K"),
        // L
        LanguageInfo(id: "lua", displayName: "Lua", extensions: ["lua"], category: "L"),
        // M
        LanguageInfo(id: "makefile", displayName: "Makefile", extensions: ["mk", "mak", "makefile"], category: "M"),
        LanguageInfo(id: "markdown", displayName: "Markdown", extensions: ["md", "markdown", "mdown"], category: "M"),
        // O
        LanguageInfo(id: "objc", displayName: "Objective-C", extensions: ["m", "mm"], category: "O"),
        // P
        LanguageInfo(id: "perl", displayName: "Perl", extensions: ["pl", "pm"], category: "P"),
        LanguageInfo(id: "php", displayName: "PHP", extensions: ["php", "phtml"], category: "P"),
        LanguageInfo(id: "powershell", displayName: "PowerShell", extensions: ["ps1", "psm1", "psd1"], category: "P"),
        LanguageInfo(id: "python", displayName: "Python", extensions: ["py", "pyw", "pyi"], category: "P"),
        // R
        LanguageInfo(id: "r", displayName: "R", extensions: ["r", "R"], category: "R"),
        LanguageInfo(id: "ruby", displayName: "Ruby", extensions: ["rb", "erb"], category: "R"),
        LanguageInfo(id: "rust", displayName: "Rust", extensions: ["rs"], category: "R"),
        // S
        LanguageInfo(id: "scala", displayName: "Scala", extensions: ["scala", "sc"], category: "S"),
        LanguageInfo(id: "scss", displayName: "SCSS / Sass", extensions: ["scss", "sass"], category: "S"),
        LanguageInfo(id: "sql", displayName: "SQL", extensions: ["sql"], category: "S"),
        LanguageInfo(id: "swift", displayName: "Swift", extensions: ["swift"], category: "S"),
        // T
        LanguageInfo(id: "toml", displayName: "TOML", extensions: ["toml"], category: "T"),
        LanguageInfo(id: "typescript", displayName: "TypeScript", extensions: ["ts", "tsx"], category: "T"),
        // V
        LanguageInfo(id: "vb", displayName: "Visual Basic", extensions: ["vb", "bas"], category: "V"),
        LanguageInfo(id: "vue", displayName: "Vue", extensions: ["vue"], category: "V"),
        // X
        LanguageInfo(id: "xml", displayName: "XML", extensions: ["xml", "plist", "svg", "xsl", "xsd"], category: "X"),
        // Y
        LanguageInfo(id: "yaml", displayName: "YAML", extensions: ["yml", "yaml"], category: "Y")
    ]

    private lazy var extensionMap: [String: String] = {
        var map: [String: String] = [:]
        for language in languages {
            for ext in language.extensions {
                map[ext.lowercased()] = language.id
            }
        }
        // Special filenames
        map["dockerfile"] = "dockerfile"
        map["makefile"] = "makefile"
        map["cmakelists.txt"] = "cmake"
        return map
    }()

    public func languageID(forExtension ext: String) -> String {
        extensionMap[ext.lowercased()] ?? "plaintext"
    }

    public func languageID(forFilename name: String) -> String {
        let lower = name.lowercased()
        if lower == "dockerfile" || lower.hasPrefix("dockerfile.") { return "dockerfile" }
        if lower == "makefile" || lower == "gnumakefile" { return "makefile" }
        if lower == "cmakelists.txt" { return "cmake" }
        return languageID(forExtension: (name as NSString).pathExtension)
    }

    func info(for id: String) -> LanguageInfo {
        languages.first { $0.id == id } ?? languages[0]
    }

    public func displayName(for id: String) -> String {
        info(for: id).displayName
    }

    var categories: [String] {
        Array(Set(languages.map(\.category))).sorted()
    }

    func languages(in category: String) -> [LanguageInfo] {
        languages.filter { $0.category == category }.sorted { $0.displayName < $1.displayName }
    }

    /// Maps app language IDs → Neon Tree-sitter language names.
    func treeSitterLanguageName(for id: String) -> String? {
        switch id {
        case "plaintext", "diff", "dockerfile", "graphql", "julia", "lua",
             "makefile", "perl", "r", "scala", "vb", "cmake", "actionscript":
            return nil
        case "xml", "vue": return "html"
        case "scss": return "css"
        case "kotlin": return "java"
        case "objc": return "c"
        case "batch", "powershell": return "bash"
        case "ini": return "toml"
        default: return id
        }
    }
}
