import SwiftUI

/// An open composition book filling the whole screen.
///
/// Held upright it shows one page. Turned sideways or unfolded it opens into
/// a two page spread. It reopens at the last page you had open.
struct NotebookView: View {
    let notebookID: UUID
    var onClose: () -> Void

    @Environment(NotebookStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentPage: Int
    @State private var showingPages = false
    /// Bumped to rebuild the pager after pages are deleted.
    @State private var pagerVersion = 0

    init(notebookID: UUID, startPage: Int, onClose: @escaping () -> Void) {
        self.notebookID = notebookID
        self.onClose = onClose
        _currentPage = State(initialValue: startPage)
    }

    var body: some View {
        GeometryReader { geo in
            let spread = geo.size.width > geo.size.height
            ZStack {
                if let notebook = store.notebook(notebookID) {
                    BookPager(
                        store: store,
                        notebook: notebook,
                        spread: spread,
                        pen: settings.pen,
                        dark: colorScheme == .dark,
                        currentPage: $currentPage,
                        onShowPages: { showingPages = true }
                    )
                    .id("\(spread)-\(pagerVersion)")

                    if spread {
                        Spine()
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                PenMenu(
                    canUndo: store.canUndo(in: notebookID),
                    canRedo: store.canRedo(in: notebookID),
                    onUndo: undo,
                    onRedo: redo,
                    onClose: close
                )
                .padding(.trailing, 22)
                .padding(.bottom, 26)
                // Keep the open menu clear of the camera at the top of the screen.
                .padding(.top, 64)
            }
            .sheet(isPresented: $showingPages) {
                if let notebook = store.notebook(notebookID) {
                    PageGridSheet(
                        notebook: notebook,
                        visiblePages: spread
                            ? Set([currentPage - currentPage % 2, currentPage - currentPage % 2 + 1])
                            : Set([currentPage]),
                        dark: colorScheme == .dark,
                        onSelect: { currentPage = $0 },
                        onDelete: deletePages
                    )
                }
            }
        }
        .ignoresSafeArea()
        .background(Color(PaperPalette(dark: colorScheme == .dark).paper).ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear(perform: evenUpPages)
        .onDisappear { store.flushSaves() }
        .onChange(of: currentPage) { _, page in
            store.setLastPage(page, of: notebookID)
        }
    }

    /// Older notebooks may have an odd page count. Round up so a spread is never half empty.
    private func evenUpPages() {
        if let count = store.notebook(notebookID)?.pages.count {
            store.ensurePageCount(notebookID, count)
        }
    }

    private func close() {
        onClose()
    }

    private func deletePages(_ pageIDs: Set<UUID>) {
        store.deletePages(pageIDs, in: notebookID)
        let count = store.notebook(notebookID)?.pages.count ?? 1
        currentPage = min(currentPage, count - 1)
        pagerVersion += 1
    }

    private func undo() {
        if let page = store.undo(in: notebookID) { show(page) }
    }

    private func redo() {
        if let page = store.redo(in: notebookID) { show(page) }
    }

    /// Flips to a page that undo or redo just changed.
    private func show(_ pageID: UUID) {
        if let index = store.notebook(notebookID)?.pages.firstIndex(where: { $0.id == pageID }) {
            currentPage = index
        }
    }
}

/// The fold down the middle of an open composition book: a soft crease
/// shadow in the paper's own tones rather than a drawn line.
struct Spine: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let depth = colorScheme == .dark ? 0.35 : 0.1
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0), location: 0),
                .init(color: .black.opacity(depth * 0.5), location: 0.4),
                .init(color: .black.opacity(depth), location: 0.5),
                .init(color: .black.opacity(depth * 0.5), location: 0.6),
                .init(color: .black.opacity(0), location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: 18)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
