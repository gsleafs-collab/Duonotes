import PencilKit
import SwiftUI

/// Thumbnails of every page, opened by tapping a page number.
/// Tap a page to jump to it. Use Select to delete several pages, or touch
/// and hold one page to delete it.
struct PageGridSheet: View {
    let notebook: Notebook
    let visiblePages: Set<Int>
    let dark: Bool
    var onSelect: (Int) -> Void
    var onDelete: (Set<UUID>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var pendingDelete: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92, maximum: 140), spacing: 14)], spacing: 18) {
                        ForEach(Array(notebook.pages.enumerated()), id: \.element.id) { index, page in
                            cell(page, index: index)
                                .id(index)
                        }
                    }
                    .padding(16)
                }
                .onAppear {
                    if let first = visiblePages.min() {
                        proxy.scrollTo(first, anchor: .center)
                    }
                }
            }
            .navigationTitle(selecting ? selectionTitle : notebook.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .confirmationDialog(
                pendingDelete.count == 1 ? "Delete this page?" : "Delete \(pendingDelete.count) pages?",
                isPresented: Binding(
                    get: { !pendingDelete.isEmpty },
                    set: { if !$0 { pendingDelete = [] } }
                ),
                titleVisibility: .visible
            ) {
                Button(pendingDelete.count == 1 ? "Delete Page" : "Delete \(pendingDelete.count) Pages", role: .destructive) {
                    onDelete(pendingDelete)
                    selected.subtract(pendingDelete)
                    pendingDelete = []
                    selecting = false
                }
            } message: {
                Text("The writing on these pages will be erased. This can't be undone.")
            }
        }
    }

    private var selectionTitle: String {
        selected.isEmpty ? "Select Pages" : "\(selected.count) Selected"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if selecting {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    selecting = false
                    selected = []
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Delete", role: .destructive) {
                    pendingDelete = selected
                }
                .tint(.red)
                .disabled(selected.isEmpty)
            }
        } else {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Select") { selecting = true }
            }
        }
    }

    private func cell(_ page: Page, index: Int) -> some View {
        let current = visiblePages.contains(index)
        let checked = selected.contains(page.id)
        return Button {
            if selecting {
                if checked { selected.remove(page.id) } else { selected.insert(page.id) }
            } else {
                onSelect(index)
                dismiss()
            }
        } label: {
            VStack(spacing: 6) {
                PageThumbnail(page: page, dark: dark)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(Color.accentColor, lineWidth: (selecting ? checked : current) ? 3 : 0)
                    )
                    .overlay(alignment: .bottomTrailing) {
                        if selecting {
                            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(checked ? Color.white : Color.secondary, checked ? Color.accentColor : Color.clear)
                                .background(Circle().fill(.background).padding(2))
                                .padding(6)
                        }
                    }
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit().weight(current ? .bold : .regular))
                    .foregroundStyle(current ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Page \(index + 1)")
        .accessibilityAddTraits(checked ? .isSelected : [])
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = [page.id]
            } label: {
                Label("Delete Page", systemImage: "trash")
            }
        }
    }
}

/// A small picture of one page with its writing.
struct PageThumbnail: View {
    let page: Page
    let dark: Bool

    @State private var ink: UIImage?

    var body: some View {
        ZStack {
            ThumbnailPaper(dark: dark)
            if let ink {
                Image(uiImage: ink)
                    .resizable()
            }
        }
        .aspectRatio(PaperMetrics.width / PaperMetrics.typicalHeight, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)
        .task(id: dark) {
            ink = render()
        }
    }

    private func render() -> UIImage? {
        guard !page.drawing.isEmpty, let drawing = try? PKDrawing(data: page.drawing) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: PaperMetrics.width, height: PaperMetrics.typicalHeight)
        var image: UIImage?
        // Render with the same light or dark ink colours the page shows.
        UITraitCollection(userInterfaceStyle: dark ? .dark : .light).performAsCurrent {
            image = drawing.image(from: rect, scale: 0.6)
        }
        return image
    }
}

/// Ruled paper drawn small for thumbnails.
private struct ThumbnailPaper: View {
    let dark: Bool

    var body: some View {
        Canvas { context, size in
            let palette = PaperPalette(dark: dark)
            let scale = size.width / PaperMetrics.width
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(palette.paper)))

            var rules = Path()
            var y = PaperMetrics.topMargin * scale
            while y < size.height {
                rules.move(to: CGPoint(x: 0, y: y))
                rules.addLine(to: CGPoint(x: size.width, y: y))
                y += PaperMetrics.lineSpacing * scale
            }
            context.stroke(rules, with: .color(Color(palette.rule)), lineWidth: 0.5)

            var margin = Path()
            let x = PaperMetrics.leftMargin * scale
            margin.move(to: CGPoint(x: x, y: 0))
            margin.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(margin, with: .color(Color(palette.margin)), lineWidth: 0.75)
        }
    }
}
