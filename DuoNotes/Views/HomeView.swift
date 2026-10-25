import SwiftUI

/// The front screen: the selected notebook's cover filling the display.
///
/// Tap the cover, or unfold the iPhone Duo, to open the book where you left
/// off. Folding the Duo closes it again. Switch books with the books button.
struct HomeView: View {
    /// The Duo's outer screen is about 466 points across and the inner screen
    /// about 626, so anything at least this wide on its short side is unfolded.
    private static let unfoldedWidth: CGFloat = 560

    @Environment(NotebookStore.self) private var store
    @AppStorage("selectedNotebook") private var savedSelection = ""
    @State private var selection: UUID?
    @State private var openNotebook: UUID?
    @State private var showingShelf = false

    var body: some View {
        GeometryReader { geo in
            let unfolded = min(geo.size.width, geo.size.height) >= Self.unfoldedWidth
            ZStack {
                if let openNotebook {
                    NotebookView(notebookID: openNotebook, startPage: store.lastPage(of: openNotebook)) {
                        self.openNotebook = nil
                    }
                } else if let notebook = selectedNotebook {
                    cover(notebook)
                } else {
                    emptyShelf
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onChange(of: unfolded) { _, isUnfolded in
                if isUnfolded {
                    if openNotebook == nil, !showingShelf { openNotebook = selectedNotebook?.id }
                } else {
                    openNotebook = nil
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .onAppear(perform: restoreSelection)
        .onChange(of: selection) { _, id in
            savedSelection = id?.uuidString ?? ""
        }
        .sheet(isPresented: $showingShelf) {
            BookshelfSheet(selection: $selection)
        }
    }

    /// The chosen notebook, falling back to the first one if it was deleted.
    private var selectedNotebook: Notebook? {
        if let selection, let notebook = store.notebook(selection) {
            return notebook
        }
        return store.shelf.first
    }

    private func cover(_ notebook: Notebook) -> some View {
        CompositionCover(title: notebook.title, style: notebook.cover, seed: notebook.id, fullBleed: true)
            .contentShape(Rectangle())
            .onTapGesture { openNotebook = notebook.id }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Open \(notebook.title)")
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showingShelf = true
                } label: {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(.black.opacity(0.75), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                }
                .accessibilityLabel("Switch notebook")
                .padding(.trailing, 26)
                .padding(.bottom, 30)
            }
    }

    private var emptyShelf: some View {
        ContentUnavailableView {
            Label("No Notebooks", systemImage: "book.closed")
        } description: {
            Text("Start a new composition book.")
        } actions: {
            Button("New Notebook") { showingShelf = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private func restoreSelection() {
        if let saved = UUID(uuidString: savedSelection), store.notebook(saved) != nil {
            selection = saved
        } else {
            selection = store.shelf.first?.id
        }
    }
}

/// Pick, add, rename and delete notebooks.
struct BookshelfSheet: View {
    @Binding var selection: UUID?

    @Environment(NotebookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showingNewNotebook = false
    @State private var renameTarget: Notebook?
    @State private var renameText = ""
    @State private var deleteTarget: Notebook?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96, maximum: 150), spacing: 18)], spacing: 22) {
                    ForEach(store.shelf) { notebook in
                        Button {
                            selection = notebook.id
                            dismiss()
                        } label: {
                            VStack(spacing: 6) {
                                CompositionCover(title: notebook.title, style: notebook.cover, seed: notebook.id)
                                    .aspectRatio(CompositionCover.aspectRatio, contentMode: .fit)
                                    .padding(4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(Color.accentColor, lineWidth: selection == notebook.id ? 3 : 0)
                                    )
                                Text(notebook.title)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu { menu(for: notebook) }
                    }
                }
                .padding(20)
            }
            .navigationTitle("Notebooks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewNotebook = true
                    } label: {
                        Label("New Notebook", systemImage: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text("Touch and hold a notebook to rename or delete it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .sheet(isPresented: $showingNewNotebook) {
                NewNotebookSheet { notebook in
                    selection = notebook.id
                }
            }
            .alert("Rename Notebook", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Title", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    if let target = renameTarget {
                        store.rename(target.id, to: renameText)
                    }
                }
            }
            .confirmationDialog("Delete this notebook?", isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ), titleVisibility: .visible, presenting: deleteTarget) { notebook in
                Button("Delete \"\(notebook.title)\"", role: .destructive) {
                    store.delete(notebook.id)
                }
            } message: { _ in
                Text("All of its pages will be erased. This can't be undone.")
            }
        }
    }

    @ViewBuilder
    private func menu(for notebook: Notebook) -> some View {
        Button {
            renameText = notebook.title
            renameTarget = notebook
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Menu {
            ForEach(CoverStyle.allCases) { style in
                Button(style.name) { store.setCover(notebook.id, to: style) }
            }
        } label: {
            Label("Cover Colour", systemImage: "paintpalette")
        }
        Button(role: .destructive) {
            deleteTarget = notebook
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

struct NewNotebookSheet: View {
    var onCreate: (Notebook) -> Void

    @Environment(NotebookStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var cover: CoverStyle = .classic
    @State private var id = UUID()

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("e.g. Golf Notes", text: $title)
                }
                Section("Cover") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(CoverStyle.allCases) { style in
                                Button {
                                    cover = style
                                } label: {
                                    CompositionCover(title: title, style: style, seed: id)
                                        .frame(width: 84, height: 84 / CompositionCover.aspectRatio)
                                        .padding(4)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(Color.accentColor, lineWidth: cover == style ? 3 : 0)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(style.name)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("New Notebook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let notebook = store.createNotebook(title: title, cover: cover, id: id)
                        dismiss()
                        onCreate(notebook)
                    }
                }
            }
        }
    }
}
