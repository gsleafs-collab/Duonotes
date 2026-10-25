import SwiftUI
import UIKit

/// A small round pen button that expands into the full pen menu.
struct PenMenu: View {
    var canUndo: Bool
    var canRedo: Bool
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onClose: () -> Void

    @Environment(SettingsStore.self) private var settings
    @State private var expanded = false
    @State private var editingColor: ColorSlot?

    private struct ColorSlot: Identifiable {
        let id: Int
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if expanded {
                ViewThatFits(in: .vertical) {
                    panel
                    // Short screens, such as the folded Duo turned sideways.
                    ScrollView { panel }
                        .frame(width: 330)
                }
                .transition(.scale(scale: 0.15, anchor: .bottomTrailing).combined(with: .opacity))
            } else {
                collapsedButton
                    .transition(.scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: expanded)
        .sheet(item: $editingColor) { slot in
            ColorWheelSheet(
                initial: settings.pen.colors[slot.id].uiColor,
                onChange: { settings.pen.colors[slot.id] = RGBA($0) },
                onDone: { editingColor = nil }
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: Collapsed

    private var collapsedButton: some View {
        Button {
            expanded = true
        } label: {
            Image(systemName: settings.pen.tool.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 56, height: 56)
                .background(.regularMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
                .overlay(alignment: .bottomTrailing) {
                    if settings.pen.tool.usesInk {
                        Circle()
                            .fill(settings.pen.inkColor.color)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                            .offset(x: -5, y: -5)
                    }
                }
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pen options")
    }

    // MARK: Expanded

    private var panel: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            toolRow
            if settings.pen.tool.usesInk {
                colorRow
            }
            if settings.pen.tool != .lasso {
                sizeRow
            }
            section("Finger") {
                Picker("Finger", selection: binding(\.fingerDraws)) {
                    Text("Moves ink").tag(false)
                    Text("Writes").tag(true)
                }
                .pickerStyle(.segmented)
            }
            section("Appearance") {
                Picker("Appearance", selection: binding(\.appearance)) {
                    ForEach(Appearance.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Button(action: onClose) {
                Label("Close Book", systemImage: "book.closed")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(18)
        .frame(width: 330)
        .background(panelBackground)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(.regularMaterial)
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Pen")
                .font(.title3.weight(.semibold))
            Spacer()
            iconButton("arrow.uturn.backward", label: "Undo", action: onUndo)
                .disabled(!canUndo)
            iconButton("arrow.uturn.forward", label: "Redo", action: onRedo)
                .disabled(!canRedo)
            iconButton("chevron.down", label: "Minimize") { expanded = false }
        }
    }

    private var toolRow: some View {
        HStack(spacing: 6) {
            ForEach(PenSettings.Tool.allCases) { tool in
                let selected = settings.pen.tool == tool
                Button {
                    settings.pen.tool = tool
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 18, weight: .medium))
                        Text(tool.name)
                            .font(.caption2.weight(.medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .background(selected ? Color.accentColor : Color(.tertiarySystemFill),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    private var colorRow: some View {
        section("Colour") {
            HStack(spacing: 14) {
                ForEach(0..<settings.pen.colors.count, id: \.self) { index in
                    let selected = settings.pen.selectedColor == index
                    Button {
                        if selected {
                            editingColor = ColorSlot(id: index)
                        } else {
                            settings.pen.selectedColor = index
                        }
                    } label: {
                        Circle()
                            .fill(settings.pen.colors[index].color)
                            .frame(width: 36, height: 36)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                            .padding(4)
                            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0))
                            .overlay(alignment: .bottomTrailing) {
                                if selected {
                                    Image(systemName: "paintpalette.fill")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(4)
                                        .background(Color.accentColor, in: Circle())
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(selected ? "Change colour \(index + 1)" : "Colour \(index + 1)")
                }
                Text("Tap the selected colour to pick a new one")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sizeRow: some View {
        let erasing = settings.pen.tool == .eraser
        let keyPath: WritableKeyPath<PenSettings, Double> = erasing ? \.eraserWidth : \.penWidth
        let width = binding(keyPath)
        let presets = erasing ? PenSettings.eraserPresets : PenSettings.penPresets
        let range = erasing ? PenSettings.eraserRange : PenSettings.penRange
        let largest = presets.last ?? 1

        return section(erasing ? "Eraser Size" : "Tip Size", detail: "\(Int(width.wrappedValue.rounded()))") {
            HStack(spacing: 10) {
                ForEach(presets, id: \.self) { size in
                    let selected = abs(width.wrappedValue - size) < 0.01
                    Button {
                        width.wrappedValue = size
                    } label: {
                        Circle()
                            .fill(erasing ? Color.secondary : settings.pen.inkColor.color)
                            .frame(width: 4 + 20 * size / largest, height: 4 + 20 * size / largest)
                            .frame(width: 42, height: 42)
                            .background(selected ? Color.accentColor.opacity(0.2) : Color(.tertiarySystemFill), in: Circle())
                            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: selected ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Size \(Int(size.rounded()))")
                }
            }
            Slider(value: width, in: range, step: 0.5)
        }
    }

    // MARK: Helpers

    private func section<Content: View>(_ title: String, detail: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let detail {
                    Spacer()
                    Text(detail)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<PenSettings, Value>) -> Binding<Value> {
        Binding(
            get: { settings.pen[keyPath: keyPath] },
            set: { settings.pen[keyPath: keyPath] = $0 }
        )
    }
}

/// The system colour wheel, used to change one of the three ink slots.
struct ColorWheelSheet: UIViewControllerRepresentable {
    let initial: UIColor
    var onChange: (UIColor) -> Void
    var onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIColorPickerViewController {
        let picker = UIColorPickerViewController()
        picker.title = "Ink Colour"
        picker.supportsAlpha = false
        picker.selectedColor = initial
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIColorPickerViewController, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIColorPickerViewControllerDelegate {
        var parent: ColorWheelSheet

        init(_ parent: ColorWheelSheet) {
            self.parent = parent
        }

        func colorPickerViewController(_ viewController: UIColorPickerViewController, didSelect color: UIColor, continuously: Bool) {
            parent.onChange(color)
        }

        func colorPickerViewControllerDidFinish(_ viewController: UIColorPickerViewController) {
            parent.onDone()
        }
    }
}
