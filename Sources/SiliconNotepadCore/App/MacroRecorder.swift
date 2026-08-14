import Foundation

public enum MacroAction: Codable, Equatable {
    case insertText(String)
    case deleteBackward
    case deleteForward
    case newLine
    case duplicateLine
    case moveLineUp
    case moveLineDown
    case findNext
    case findPrevious
    case toggleBookmark
    case goToLine(Int)
}

public final class MacroRecorder {
    public static let shared = MacroRecorder()

    public private(set) var isRecording = false
    public private(set) var actions: [MacroAction] = []
    public var savedMacro: [MacroAction] = []

    private init() {}

    public func start() {
        actions = []
        isRecording = true
    }

    public func stop() {
        isRecording = false
        if !actions.isEmpty {
            savedMacro = actions
        }
    }

    public func record(_ action: MacroAction) {
        guard isRecording else { return }
        actions.append(action)
    }

    public var canPlay: Bool {
        !savedMacro.isEmpty || (!isRecording && !actions.isEmpty)
    }

    public var playbackActions: [MacroAction] {
        if !savedMacro.isEmpty { return savedMacro }
        return actions
    }
}
