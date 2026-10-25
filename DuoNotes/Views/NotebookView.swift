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
    @State private var coverOpen = false
    @State private var showingPages = false

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
                    .id(spread)

                    if spread {
                        Spine()
                    }

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
                .opacity(coverOpen ? 1 : 0)
                .allowsHitTesting(coverOpen)
            }
            .sheet(isPresented: $showingPages) {
                if let notebook = store.notebook(notebookID) {
                    PageGridSheet(
                        notebook: notebook,
                        visiblePages: spread
                            ? Set([currentPage - currentPage % 2, currentPage - currentPage % 2 + 1])
                            : Set([currentPage]),
                        dark: colorScheme == .dark,
                        onSelect: { currentPage = $0 }
                    )
                }
            }
        }
        .ignoresSafeArea()
        .background(Color(PaperPalette(dark: colorScheme == .dark).paper).ignoresSafeArea())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear(perform: open)
        .onDisappear { store.flushSaves() }
        .onChange(of: currentPage) { _, page in
            store.setLastPage(page, of: notebookID)
        }
    }

    /// The front cover. Upright it swings open on its spine. In a spread it
    /// lifts away, since the whole screen showed the cover a moment ago.
    private func cover(_ notebook: Notebook, spread: Bool, size: CGSize) -> some View {
        CompositionCover(title: notebook.title, style: notebook.cover, seed: notebook.id, fullBleed: true)
            .frame(width: size.width, height: size.height)
            .rotation3DEffect(.degrees(!spread && coverOpen ? -90 : 0), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.4)
            .scaleEffect(spread && coverOpen ? 1.06 : 1)
            .opacity(coverOpen ? 0 : 1)
            .allowsHitTesting(false)
    }

    private func open() {
        // Older notebooks may have an odd page count. Round up so a spread is never half empty.
        if let count = store.notebook(notebookID)?.pages.count {
            store.ensurePageCount(notebookID, count)
        }
        withAnimation(.easeIn(duration: 0.5).delay(0.1)) {
            coverOpen = true
        }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.4)) {
            coverOpen = false
        } completion: {
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

/// The sewn seam down the middle of an open composition book.
struct Spine: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.15), location: 0.42),
                    .init(color: .black.opacity(0.3), location: 0.5),
                    .init(color: .black.opacity(0.15), location: 0.58),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 30)

            // Stitching.
            Line()
                .stroke(Color(white: 0.8), style: StrokeStyle(lineWidth: 1.2, dash: [6, 8]))
                .frame(width: 2)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.midX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            }
        }
    }
}
