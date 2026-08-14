import Foundation

/// Tracks on-disk modification times for open file-backed documents.
final class FileMonitor {
    static let shared = FileMonitor()

    private struct Snapshot {
        let date: Date
        let exists: Bool
    }

    private var snapshots: [UUID: Snapshot] = [:]
    private let lock = NSLock()

    private init() {}

    func snapshot(document: Document) {
        guard let url = document.fileURL else { return }
        lock.lock()
        defer { lock.unlock() }
        snapshots[document.id] = Snapshot(date: modificationDate(of: url), exists: fileExists(url))
    }

    func clear(documentID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        snapshots.removeValue(forKey: documentID)
    }

    func changedDocuments(in documents: [Document]) -> [Document] {
        lock.lock()
        defer { lock.unlock() }
        var changed: [Document] = []
        for doc in documents {
            guard let url = doc.fileURL else { continue }
            guard let previous = snapshots[doc.id] else { continue }
            let exists = fileExists(url)
            let current = modificationDate(of: url)
            // Modified while open, deleted/renamed, or recreated after deletion.
            if (exists && previous.exists && current > previous.date)
                || (exists != previous.exists) {
                changed.append(doc)
            }
        }
        return changed
    }

    func refreshSnapshot(document: Document) {
        snapshot(document: document)
    }

    private func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}
