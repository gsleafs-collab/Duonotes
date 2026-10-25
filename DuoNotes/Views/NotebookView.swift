import SwiftUI

/// How many pages to show at once.
enum PageLayout: String, CaseIterable, Identifiable {
    case automatic, one, two

    var id: String { rawValue }

    var name: String {
        switch self {
        case .automatic: return "Automatic"
        case .one: return "One Page"
        case .two: return "Two Pages"
        }
    }
}

/// An open composition book.
///
/// Folded, the iPhone Duo shows one page. Unfolded and turned sideways, the
/// notebook opens into a two page spread with the spine down the middle.
struct NotebookView: View {
    let notebookID: UUID

    @Environment(NotebookStore.self) private var store
    @State private var tool = ToolState()
    @State private var fingerDraws = false
    @State private var layout: PageLayout = .automatic
    @State private var firstPage = 0
    @State private var turningForward = true
    @State private var coverAngle: Double = 0
    @State private var coverOpen = false

    var body: some View {
        Group {
            if let notebook = store.notebook(notebookID) {
                GeometryReader { geo in
                    let spread = showsSpread(in: geo.size)
                    let left = spread ? firstPage - firstPage % 2 : firstPage
                    VStack(spacing: 10) {
                        openBook(notebook, left: left, spread: spread)
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        ToolPalette(tool: $tool, fingerDraws: $fingerDraws)
                        pager(notebook, left: left, spread: spread)
                    }
                    .padding(.bottom, 6)
                }
                .navigationTitle(notebook.title)
            } else {
                ContentUnavailableView("Notebook Not Found", systemImage: "book.closed")
            }
        }
        .background(Desk().ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    if let page = store.undo(in: notebookID) { show(page) }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!store.canUndo(in: notebookID))

                Button {
                    if let page = store.redo(in: notebookID) { show(page) }
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!store.canRedo(in: notebookID))

                Menu {
                    Picker("Pages", selection: $layout) {
                        ForEach(PageLayout.allCases) { Text($0.name).tag($0) }
                    }
                } label: {
                    Label("Pages", systemImage: "book.pages")
                }
            }
        }
        .onAppear(perform: openCover)
    }

    /// Two pages when there's room for a proper open book, such as the unfolded Duo turned sideways.
    private func showsSpread(in size: CGSize) -> Bool {
        switch layout {
        case .one: return false
        case .two: return true
        case .automatic: return size.width > size.height && size.width >= 760
        }
    }

    // MARK: Pages

    private func openBook(_ notebook: Notebook, left: Int, spread: Bool) -> some View {
        let bookSize = CGSize(width: PaperMetrics.size.width * (spread ? 2 : 1), height: PaperMetrics.size.height)
        return ZStack {
            // The open cover peeking out behind the paper.
            RoundedRectangle(cornerRadius: 6)
                .fill(notebook.cover.ink)
                .padding(-7)
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)

            HStack(spacing: 0) {
                if spread {
                    pageView(notebook, index: left, side: .left, spread: spread)
                }
                pageView(notebook, index: spread ? left + 1 : left, side: spread ? .right : .single, spread: spread)
                    .overlay { closedCover(notebook) }
            }

            if spread {
                Spine()
            }
        }
        .aspectRatio(bookSize, contentMode: .fit)
    }

    @ViewBuilder
    private func pageView(_ notebook: Notebook, index: Int, side: PageSide, spread: Bool) -> some View {
        if index < notebook.pages.count {
            let page = notebook.pages[index]
            PaperPage(
                page: page,
                pageNumber: index + 1,
                side: side,
                tool: tool,
                fingerDraws: fingerDraws,
                onChange: { store.setDrawing($0, notebook: notebookID, page: page.id) },
                onSwipe: { turn($0, spread: spread) }
            )
            .id(page.id)
            .transition(.push(from: turningForward ? .trailing : .leading))
        } else {
            LinedPaper()
                .aspectRatio(PaperMetrics.size, contentMode: .fit)
        }
    }

    // MARK: Opening the cover

    @ViewBuilder
    private func closedCover(_ notebook: Notebook) -> some View {
        if !coverOpen {
            CompositionCover(title: notebook.title, style: notebook.cover, seed: notebook.id)
                .rotation3DEffect(.degrees(coverAngle), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.5)
                .allowsHitTesting(false)
        }
    }

    private func openCover() {
        store.ensurePageCount(notebookID, 2)
        guard !coverOpen else { return }
        withAnimation(.easeIn(duration: 0.5).delay(0.25)) {
            coverAngle = -90
        } completion: {
            coverOpen = true
        }
    }

    // MARK: Turning pages

    private func pager(_ notebook: Notebook, left: Int, spread: Bool) -> some View {
        let label = spread
            ? "Pages \(left + 1)–\(left + 2)"
            : "Page \(left + 1)"
        return HStack(spacing: 24) {
            Button {
                turn(.backward, spread: spread)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(left == 0)

            Text(label)
                .font(.footnote.monospacedDigit())
                .frame(minWidth: 90)

            Button {
                turn(.forward, spread: spread)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(left + (spread ? 2 : 1) >= NotebookStore.maxPages)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .contain)
    }

    private func turn(_ direction: SwipeDirection, spread: Bool) {
        let step = spread ? 2 : 1
        let left = spread ? firstPage - firstPage % 2 : firstPage
        let target = direction == .forward ? left + step : left - step
        guard target >= 0, target + step <= NotebookStore.maxPages else { return }
        store.ensurePageCount(notebookID, target + step)
        turningForward = direction == .forward
        withAnimation(.easeInOut(duration: 0.3)) {
            firstPage = target
        }
    }

    /// Jumps to a page, used after undo or redo changes a page that's off screen.
    private func show(_ pageID: UUID) {
        guard let index = store.notebook(notebookID)?.pages.firstIndex(where: { $0.id == pageID }),
              index != firstPage else { return }
        turningForward = index > firstPage
        withAnimation(.easeInOut(duration: 0.3)) {
            firstPage = index
        }
    }
}

/// The sewn binding down the middle of an open composition book.
struct Spine: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.22), location: 0.45),
                    .init(color: .black.opacity(0.35), location: 0.5),
                    .init(color: .black.opacity(0.22), location: 0.55),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 34)

            // Stitching.
            Line()
                .stroke(Color(white: 0.85), style: StrokeStyle(lineWidth: 1.2, dash: [6, 8]))
                .frame(width: 1)
        }
        .allowsHitTesting(false)
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

/// Pens, colours, thickness and the finger mode switch.
struct ToolPalette: View {
    @Binding var tool: ToolState
    @Binding var fingerDraws: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(ToolState.Kind.allCases) { kind in
                    Button {
                        tool.kind = kind
                    } label: {
                        Image(systemName: kind.symbol)
                            .font(.body)
                            .frame(width: 34, height: 34)
                            .background(tool.kind == kind ? Color.accentColor.opacity(0.25) : .clear, in: Circle())
                    }
                    .accessibilityLabel(kind.name)
                }

                Divider().frame(height: 24)

                ForEach(ToolState.Ink.allCases) { ink in
                    Button {
                        tool.ink = ink
                        if !tool.kind.usesInk { tool.kind = .pen }
                    } label: {
                        Circle()
                            .fill(ink.color)
                            .frame(width: 22, height: 22)
                            .padding(3)
                            .overlay(Circle().strokeBorder(.primary, lineWidth: tool.ink == ink ? 2 : 0))
                    }
                    .accessibilityLabel(ink.name)
                }

                Divider().frame(height: 24)

                Menu {
                    Picker("Thickness", selection: $tool.thickness) {
                        ForEach(ToolState.Thickness.allCases) { Text($0.name).tag($0) }
                    }
                } label: {
                    Image(systemName: "lineweight")
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel("Thickness")

                Button {
                    fingerDraws.toggle()
                } label: {
                    Label(fingerDraws ? "Finger writes" : "Finger moves",
                          systemImage: fingerDraws ? "hand.draw" : "hand.point.up.left")
                        .font(.footnote)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.regularMaterial, in: Capsule())
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
    }
}
