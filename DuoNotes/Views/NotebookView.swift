import SwiftUI

/// An open composition book filling the whole screen.
///
/// Held upright it shows one page. Turned sideways it opens into a two page
/// spread. The cover swings open on arrival and closes again on the way out.
struct NotebookView: View {
    let notebookID: UUID
    var onClose: () -> Void

    @Environment(NotebookStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @State private var currentPage = 0
    @State private var coverAngle: Double = 0
    @State private var coverShown = true

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
                        currentPage: $currentPage
                    )
                    .id(spread)

                    cover(notebook, spread: spread, size: geo.size)
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
                .opacity(coverShown ? 0 : 1)
                .allowsHitTesting(!coverShown)
            }
        }
        .ignoresSafeArea()
        .background(Color(PaperPalette(dark: colorScheme == .dark).paper).ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear(perform: open)
    }

    /// The front cover. In a spread it sits over the right page and hinges on the spine.
    private func cover(_ notebook: Notebook, spread: Bool, size: CGSize) -> some View {
        CompositionCover(title: notebook.title, style: notebook.cover, seed: notebook.id, fullBleed: true)
            .frame(width: spread ? size.width / 2 : size.width, height: size.height)
            .rotation3DEffect(.degrees(coverAngle), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.4)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .opacity(coverShown ? 1 : 0)
            .allowsHitTesting(false)
    }

    private func open() {
        // Older notebooks may have an odd page count. Round up so a spread is never half empty.
        if let count = store.notebook(notebookID)?.pages.count {
            store.ensurePageCount(notebookID, count)
        }
        withAnimation(.easeIn(duration: 0.55).delay(0.15)) {
            coverAngle = -90
        } completion: {
            coverShown = false
        }
    }

    private func close() {
        coverShown = true
        withAnimation(.easeOut(duration: 0.45)) {
            coverAngle = 0
        } completion: {
            store.flushSaves()
            onClose()
        }
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
