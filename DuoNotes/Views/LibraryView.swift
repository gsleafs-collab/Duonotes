import SwiftUI

/// The shelf of notebooks.
struct LibraryView: View {
    @Environment(NotebookStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var path: [UUID] = []
    @State private var showingNewNotebook = false
    @State private var renameTarget: Notebook?
    @State private var renameText = ""
    @State private var deleteTarget: Notebook?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 200), spacing: 24)], spacing: 28) {
                    ForEach(store.recentNotebooks) { notebook in
                        NavigationLink(value: notebook.id) {
                            VStack(spacing: 8) {
                                CompositionCover(title: notebook.title, style: notebook.cover, seed: notebook.id)
                                    .aspectRatio(CompositionCover.aspectRatio, contentMode: .fit)
                                Text(notebook.updatedAt, format: .dateTime.month().day())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu { menu(for: notebook) }
                    }
                }
                .padding(20)
            }
            .background(Desk().ignoresSafeArea())
            .navigationTitle("DuoNotes")
            .navigationDestination(for: UUID.self) { id in
                NotebookView(notebookID: id)
            }
            .toolbar {
                Button {
                    showingNewNotebook = true
                } label: {
                    Label("New Notebook", systemImage: "plus")
                }
            }
            .overlay {
                if store.notebooks.isEmpty {
                    ContentUnavailableView("No Notebooks", systemImage: "book.closed",
                                           description: Text("Tap + to start a composition book."))
                }
            }
            .sheet(isPresented: $showingNewNotebook) {
                NewNotebookSheet { notebook in
                    path.append(notebook.id)
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
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flushSaves() }
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
            Label("Cover", systemImage: "paintpalette")
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

/// Warm wooden desk behind the notebooks.
struct Desk: View {
    var body: some View {
        LinearGradient(
            colors: [Color(red: 0.42, green: 0.29, blue: 0.20), Color(red: 0.30, green: 0.20, blue: 0.14)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
