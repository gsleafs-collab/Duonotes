import Observation
import PencilKit
import SwiftUI

/// A colour that can be saved.
struct RGBA: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(_ color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(red: min(max(Double(r), 0), 1),
                  green: min(max(Double(g), 0), 1),
                  blue: min(max(Double(b), 0), 1))
    }

    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: 1) }
    var color: Color { Color(uiColor) }
}

enum Appearance: String, Codable, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Everything chosen in the pen menu.
struct PenSettings: Codable, Equatable {
    enum Tool: String, Codable, CaseIterable, Identifiable {
        case pen, pencil, marker, eraser, lasso

        var id: String { rawValue }
        var name: String { rawValue.capitalized }

        var symbol: String {
            switch self {
            case .pen: return "pencil.tip"
            case .pencil: return "pencil"
            case .marker: return "highlighter"
            case .eraser: return "eraser"
            case .lasso: return "lasso"
            }
        }

        var usesInk: Bool { self == .pen || self == .pencil || self == .marker }
    }

    static let penPresets: [Double] = [1.5, 3, 5, 8]
    static let eraserPresets: [Double] = [8, 16, 30, 50]

    var tool: Tool = .pen
    static let defaultColors: [RGBA] = [
        RGBA(red: 0.11, green: 0.11, blue: 0.13), // black
        RGBA(red: 0.12, green: 0.33, blue: 0.78), // blue
        RGBA(red: 0.80, green: 0.16, blue: 0.16), // red
        RGBA(red: 0.10, green: 0.52, blue: 0.27), // green
        RGBA(red: 0.55, green: 0.24, blue: 0.75), // purple
    ]

    /// Five ink slots. Black ink shows as white on dark paper.
    var colors: [RGBA] = PenSettings.defaultColors
    var selectedColor = 0
    var penWidth: Double = 3
    var eraserWidth: Double = 16
    var fingerDraws = false
    var appearance: Appearance = .system
    /// Scribbling quickly over writing erases it.
    var scribbleToErase = true

    var inkColor: RGBA {
        colors.indices.contains(selectedColor) ? colors[selectedColor] : colors[0]
    }

    var pkTool: PKTool {
        let width = CGFloat(penWidth)
        switch tool {
        case .pen:
            return PKInkingTool(.pen, color: inkColor.uiColor, width: width)
        case .pencil:
            return PKInkingTool(.pencil, color: inkColor.uiColor, width: width * 1.5)
        case .marker:
            return PKInkingTool(.marker, color: inkColor.uiColor, width: width * 4)
        case .eraser:
            return PKEraserTool(.bitmap, width: CGFloat(eraserWidth))
        case .lasso:
            return PKLassoTool()
        }
    }
}

extension PenSettings {
    /// Reads saved settings, using the default for anything missing, so
    /// adding a new setting never resets the ones already chosen.
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tool = try container.decodeIfPresent(Tool.self, forKey: .tool) ?? tool
        colors = try container.decodeIfPresent([RGBA].self, forKey: .colors) ?? colors
        // Settings saved with fewer slots get the remaining default colours.
        if colors.count < Self.defaultColors.count {
            colors += Self.defaultColors[colors.count...]
        }
        selectedColor = try container.decodeIfPresent(Int.self, forKey: .selectedColor) ?? selectedColor
        penWidth = try container.decodeIfPresent(Double.self, forKey: .penWidth) ?? penWidth
        eraserWidth = try container.decodeIfPresent(Double.self, forKey: .eraserWidth) ?? eraserWidth
        fingerDraws = try container.decodeIfPresent(Bool.self, forKey: .fingerDraws) ?? fingerDraws
        appearance = try container.decodeIfPresent(Appearance.self, forKey: .appearance) ?? appearance
        scribbleToErase = try container.decodeIfPresent(Bool.self, forKey: .scribbleToErase) ?? scribbleToErase
    }
}

/// Keeps the pen menu choices between launches.
@Observable
final class SettingsStore {
    private static let key = "penSettings"

    var pen: PenSettings {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(PenSettings.self, from: data) {
            pen = saved
        } else {
            pen = PenSettings()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(pen) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
