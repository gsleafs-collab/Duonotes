import Foundation
import Observation

/// Owns every notebook, saves them to disk and keeps undo history.
@Observable
final class NotebookStore {
    static let maxPages = 200
    private static let undoLimit = 50

    private(set) var notebooks: [Notebook] = []

    /// One entry per edit: the page that changed and its drawing before the change.
    private struct Edit {
        var page: UUID
        var drawing: Data
    }

    // Keyed by notebook ID so undo works across pages of the same notebook.
    private var undoStacks: [UUID: [Edit]] = [:]
    private var redoStacks: [UUID: [Edit]] = [:]

    @ObservationIgnored private var pendingSaves: [UUID: DispatchWorkItem] = [:]
    @ObservationIgnored private let folder: URL

    init(folder: URL? = nil) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.folder = folder ?? documents.appendingPathComponent("Notebooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
        load()
        if notebooks.isEmpty {
            createNotebook(title: "My First Notebook", cover: .classic)
        }
    }

    /// Notebooks in the order they were made, so swiping between covers stays predictable.
    var shelf: [Notebook] {
        notebooks.sorted { $0.createdAt < $1.createdAt }
    }

    func notebook(_ id: UUID) -> Notebook? {
        notebooks.first { $0.id == id }
    }

    // MARK: Notebooks

    @discardableResult
    func createNotebook(title: String, cover: CoverStyle, id: UUID = UUID()) -> Notebook {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let notebook = Notebook(id: id, title: trimmed.isEmpty ? "Untitled" : trimmed, cover: cover)
        notebooks.append(notebook)
        saveNow(notebook.id)
        return notebook
    }

    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate(id) { $0.title = trimmed }
    }

    func setCover(_ id: UUID, to cover: CoverStyle) {
        mutate(id) { $0.cover = cover }
    }

    // MARK: Last open page

    private static let lastPagesKey = "lastPages"

    /// The page the notebook was last open at, so it reopens where you left off.
    func lastPage(of id: UUID) -> Int {
        let pages = UserDefaults.standard.dictionary(forKey: Self.lastPagesKey) as? [String: Int]
        let page = pages?[id.uuidString] ?? 0
        let count = notebook(id)?.pages.count ?? 1
        return min(max(page, 0), max(count - 1, 0))
    }

    func setLastPage(_ page: Int, of id: UUID) {
        var pages = UserDefaults.standard.dictionary(forKey: Self.lastPagesKey) as? [String: Int] ?? [:]
        pages[id.uuidString] = page
        UserDefaults.standard.set(pages, forKey: Self.lastPagesKey)
    }

    func delete(_ id: UUID) {
        var pages = UserDefaults.standard.dictionary(forKey: Self.lastPagesKey) as? [String: Int] ?? [:]
        pages[id.uuidString] = nil
        UserDefaults.standard.set(pages, forKey: Self.lastPagesKey)
        pendingSaves[id]?.cancel()
        pendingSaves[id] = nil
        undoStacks[id] = nil
        redoStacks[id] = nil
        notebooks.removeAll { $0.id == id }
        try? FileManager.default.removeItem(at: fileURL(id))
    }

    /// Adds blank pages until the notebook has at least `count` pages.
    /// Pages come in pairs, like sheets of paper, so a two page spread is always complete.
    func ensurePageCount(_ id: UUID, _ count: Int) {
        let target = min(count + count % 2, Self.maxPages)
        guard let notebook = notebook(id), notebook.pages.count < target else { return }
        mutate(id) { notebook in
            while notebook.pages.count < target {
                notebook.pages.append(Page())
            }
        }
    }

    /// Removes pages for good. The notebook keeps an even number of pages,
    /// with at least two, so blank paper is added at the end if needed.
    func deletePages(_ pageIDs: Set<UUID>, in id: UUID) {
        guard !pageIDs.isEmpty else { return }
        undoStacks[id]?.removeAll { pageIDs.contains($0.page) }
        redoStacks[id]?.removeAll { pageIDs.contains($0.page) }
        mutate(id) { notebook in
            notebook.pages.removeAll { pageIDs.contains($0.id) }
            let target = max(2, notebook.pages.count + notebook.pages.count % 2)
            while notebook.pages.count < target {
                notebook.pages.append(Page())
            }
        }
    }

    // MARK: Drawings

    func drawing(notebook id: UUID, page pageID: UUID) -> Data? {
        notebook(id)?.pages.first { $0.id == pageID }?.drawing
    }

    func setDrawing(_ data: Data, notebook id: UUID, page pageID: UUID) {
        guard let old = drawing(notebook: id, page: pageID), old != data else { return }
        var stack = undoStacks[id, default: []]
        stack.append(Edit(page: pageID, drawing: old))
        if stack.count > Self.undoLimit { stack.removeFirst() }
        undoStacks[id] = stack
        redoStacks[id] = nil
        write(data, notebook: id, page: pageID)
    }

    func canUndo(in id: UUID) -> Bool { !(undoStacks[id]?.isEmpty ?? true) }
    func canRedo(in id: UUID) -> Bool { !(redoStacks[id]?.isEmpty ?? true) }

    /// Reverts the most recent edit and returns the page it touched.
    @discardableResult
    func undo(in id: UUID) -> UUID? {
        guard let edit = undoStacks[id]?.popLast(),
              let current = drawing(notebook: id, page: edit.page) else { return nil }
        redoStacks[id, default: []].append(Edit(page: edit.page, drawing: current))
        write(edit.drawing, notebook: id, page: edit.page)
        return edit.page
    }

    @discardableResult
    func redo(in id: UUID) -> UUID? {
        guard let edit = redoStacks[id]?.popLast(),
              let current = drawing(notebook: id, page: edit.page) else { return nil }
        undoStacks[id, default: []].append(Edit(page: edit.page, drawing: current))
        write(edit.drawing, notebook: id, page: edit.page)
        return edit.page
    }

    private func write(_ data: Data, notebook id: UUID, page pageID: UUID) {
        mutate(id) { notebook in
            if let index = notebook.pages.firstIndex(where: { $0.id == pageID }) {
                notebook.pages[index].drawing = data
            }
        }
    }

    private func mutate(_ id: UUID, _ change: (inout Notebook) -> Void) {
        guard let index = notebooks.firstIndex(where: { $0.id == id }) else { return }
        change(&notebooks[index])
        notebooks[index].updatedAt = Date()
        scheduleSave(id)
    }

    // MARK: Persistence

    /// Writes any unsaved changes right away. Call when the app goes to the background.
    func flushSaves() {
        for id in Array(pendingSaves.keys) {
            pendingSaves[id]?.cancel()
            saveNow(id)
        }
    }

    private func fileURL(_ id: UUID) -> URL {
        folder.appendingPathComponent("\(id.uuidString).notebook")
    }

    private func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let decoder = PropertyListDecoder()
        notebooks = files
            .filter { $0.pathExtension == "notebook" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(Notebook.self, from: data)
            }
    }

    // Saving is debounced so a burst of strokes becomes one disk write.
    private func scheduleSave(_ id: UUID) {
        pendingSaves[id]?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.saveNow(id) }
        pendingSaves[id] = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: item)
    }

    private func saveNow(_ id: UUID) {
        pendingSaves[id] = nil
        guard let notebook = notebook(id) else { return }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(notebook) else { return }
        try? data.write(to: fileURL(id), options: .atomic)
    }
}
