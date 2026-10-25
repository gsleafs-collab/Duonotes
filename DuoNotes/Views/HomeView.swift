import SwiftUI

/// The front screen: one notebook cover filling the display.
/// Swipe to switch books, tap to open.
struct HomeView: View {
    @Environment(NotebookStore.self) private var store
    @AppStorage("selectedNotebook") private var savedSelection = ""
    @State private var selection: UUID?
    @State private var openNotebook: UUID?
    @State private var showingShelf = false

    var body: some View {
        ZStack {
            if let openNotebook {
                NotebookView(notebookID: openNotebook) {
                    self.openNotebook = nil
                }
            } else if store.notebooks.isEmpty {
                emptyShelf
            } else {
                covers
            }
        }
        .statusBarHidden()
        .onAppear(perform: restoreSelection)
        .onChange(of: selection) { _, id in
            savedSelection = id?.uuidString ?? ""
        }
        .onChange(of: store.notebooks.map(\.id)) { _, ids in
            if let selection, ids.contains(selection) { return }
            selection = store.shelf.first?.id
        }
        .sheet(isPresented: $showingShelf) {
            BookshelfSheet(selection: $selection)
        }
    }

    private var covers: some View {
        TabView(selection: $selection) {
            ForEach(store.shelf) { notebook in
                CompositionCover(title: notebook.title, style: notebook.cover, seed: notebook.id, fullBleed: true)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { openNotebook = notebook.id }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Open \(notebook.title)")
                    .tag(Optional(notebook.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            if store.notebooks.count > 1 {
                pageDots.padding(.bottom, 30)
            }
        }
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
            .padding(.trailing, 22)
            .padding(.bottom, 22)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(store.shelf) { notebook in
                Circle()
                    .fill(.white.opacity(notebook.id == selection ? 1 : 0.4))
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.6), in: Capsule())
        .accessibilityHidden(true)
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
