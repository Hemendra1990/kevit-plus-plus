import Foundation

public enum TextEncodingKind: String, CaseIterable, Equatable {
    case utf8 = "UTF-8"
    case utf8BOM = "UTF-8-BOM"
    case utf16LE = "UTF-16 LE"
    case utf16BE = "UTF-16 BE"
    case utf32LE = "UTF-32 LE"
    case utf32BE = "UTF-32 BE"
    case isoLatin1 = "ISO-8859-1"
    case macOSRoman = "Mac Roman"

    var stringEncoding: String.Encoding {
        switch self {
        case .utf8, .utf8BOM: return .utf8
        case .utf16LE: return .utf16LittleEndian
        case .utf16BE: return .utf16BigEndian
        case .utf32LE: return .utf32LittleEndian
        case .utf32BE: return .utf32BigEndian
        case .isoLatin1: return .isoLatin1
        case .macOSRoman: return .macOSRoman
        }
    }

    var includeBOM: Bool {
        switch self {
        case .utf8BOM, .utf16LE, .utf16BE, .utf32LE, .utf32BE: return true
        default: return false
        }
    }

    var bomBytes: [UInt8] {
        switch self {
        case .utf8BOM: return [0xEF, 0xBB, 0xBF]
        case .utf16LE: return [0xFF, 0xFE]
        case .utf16BE: return [0xFE, 0xFF]
        case .utf32LE: return [0xFF, 0xFE, 0x00, 0x00]
        case .utf32BE: return [0x00, 0x00, 0xFE, 0xFF]
        default: return []
        }
    }
}

public enum EOLStyle: String, CaseIterable, Equatable {
    case lf = "Unix (LF)"
    case crlf = "Windows (CRLF)"
    case cr = "Mac (CR)"

    public var shortName: String {
        switch self {
        case .lf: return "LF"
        case .crlf: return "CRLF"
        case .cr: return "CR"
        }
    }

    public var lineEnding: String {
        switch self {
        case .lf: return "\n"
        case .crlf: return "\r\n"
        case .cr: return "\r"
        }
    }

    public static func detect(in text: String) -> EOLStyle {
        if text.contains("\r\n") { return .crlf }
        if text.contains("\r") { return .cr }
        return .lf
    }
}

public enum EncodingDetector {
    public static func detect(data: Data) -> (encoding: TextEncodingKind, text: String)? {
        // UTF-32 BOMs (4 bytes) must be checked before the 2-byte UTF-16 BOMs.
        if data.count >= 4, data[0] == 0xFF, data[1] == 0xFE, data[2] == 0x00, data[3] == 0x00,
           let text = String(data: data.dropFirst(4), encoding: .utf32LittleEndian) {
            return (.utf32LE, text)
        }
        if data.count >= 4, data[0] == 0x00, data[1] == 0x00, data[2] == 0xFE, data[3] == 0xFF,
           let text = String(data: data.dropFirst(4), encoding: .utf32BigEndian) {
            return (.utf32BE, text)
        }
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF,
           let text = String(data: data.dropFirst(3), encoding: .utf8) {
            return (.utf8BOM, text)
        }
        if data.count >= 2, data[0] == 0xFF, data[1] == 0xFE,
           let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) {
            return (.utf16LE, text)
        }
        if data.count >= 2, data[0] == 0xFE, data[1] == 0xFF,
           let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) {
            return (.utf16BE, text)
        }
        if let text = String(data: data, encoding: .utf8) {
            return (.utf8, text)
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return (.isoLatin1, text)
        }
        if let text = String(data: data, encoding: .macOSRoman) {
            return (.macOSRoman, text)
        }
        return nil
    }

    public static func encode(_ text: String, encoding: TextEncodingKind) -> Data? {
        guard var data = text.data(using: encoding.stringEncoding, allowLossyConversion: false) else {
            return nil
        }
        if encoding.includeBOM {
            data.insert(contentsOf: encoding.bomBytes, at: 0)
        }
        return data
    }

    public static func normalizeEOL(_ text: String, to style: EOLStyle) -> String {
        let unified = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        if style == .lf { return unified }
        return unified.replacingOccurrences(of: "\n", with: style.lineEnding)
    }
}
