import Foundation

final class TabDocumentStore {
    private(set) var documents: [Document] = []
    private(set) var activeIndex: Int = -1

    var activeDocument: Document? {
        guard documents.indices.contains(activeIndex) else { return nil }
        return documents[activeIndex]
    }

    var isEmpty: Bool { documents.isEmpty }

    @discardableResult
    func add(_ document: Document, makeActive: Bool = true) -> Int {
        documents.append(document)
        let index = documents.count - 1
        if makeActive {
            activeIndex = index
        }
        return index
    }

    func setActiveIndex(_ index: Int) {
        guard documents.indices.contains(index) else { return }
        activeIndex = index
    }

    @discardableResult
    func close(at index: Int) -> Document? {
        guard documents.indices.contains(index) else { return nil }
        let removed = documents.remove(at: index)
        if documents.isEmpty {
            activeIndex = -1
        } else if activeIndex >= documents.count {
            activeIndex = documents.count - 1
        } else if index < activeIndex {
            activeIndex -= 1
        }
        return removed
    }

    func moveTab(from: Int, to: Int) {
        guard documents.indices.contains(from),
              documents.indices.contains(to),
              from != to else { return }
        let doc = documents.remove(at: from)
        documents.insert(doc, at: to)
        if activeIndex == from {
            activeIndex = to
        } else if from < activeIndex && to >= activeIndex {
            activeIndex -= 1
        } else if from > activeIndex && to <= activeIndex {
            activeIndex += 1
        }
    }

    func closeOthers(keeping index: Int) {
        guard documents.indices.contains(index) else { return }
        let keep = documents[index]
        documents = [keep]
        activeIndex = 0
    }

    func closeAll() {
        documents.removeAll()
        activeIndex = -1
    }

    func closeLeft(of index: Int) {
        guard documents.indices.contains(index), index > 0 else { return }
        documents.removeSubrange(0..<index)
        activeIndex = 0
    }

    func closeRight(of index: Int) {
        guard documents.indices.contains(index) else { return }
        if index + 1 < documents.count {
            documents.removeSubrange((index + 1)...)
        }
        activeIndex = index
    }

    func index(of document: Document) -> Int? {
        documents.firstIndex { $0.id == document.id }
    }
}
