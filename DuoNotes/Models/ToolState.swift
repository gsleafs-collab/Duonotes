import PencilKit
import SwiftUI

/// The pen the user has picked from the palette.
struct ToolState: Equatable {
    enum Kind: String, CaseIterable, Identifiable {
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

    enum Ink: String, CaseIterable, Identifiable {
        case black, blue, red, green

        var id: String { rawValue }
        var name: String { rawValue.capitalized }

        var uiColor: UIColor {
            switch self {
            case .black: return UIColor(white: 0.1, alpha: 1)
            case .blue: return UIColor(red: 0.10, green: 0.25, blue: 0.70, alpha: 1)
            case .red: return UIColor(red: 0.80, green: 0.12, blue: 0.12, alpha: 1)
            case .green: return UIColor(red: 0.10, green: 0.50, blue: 0.25, alpha: 1)
            }
        }

        var color: Color { Color(uiColor) }
    }

    enum Thickness: String, CaseIterable, Identifiable {
        case fine, medium, bold

        var id: String { rawValue }
        var name: String { rawValue.capitalized }

        var width: CGFloat {
            switch self {
            case .fine: return 2
            case .medium: return 3.5
            case .bold: return 6
            }
        }
    }

    var kind: Kind = .pen
    var ink: Ink = .black
    var thickness: Thickness = .medium

    var pkTool: PKTool {
        switch kind {
        case .pen:
            return PKInkingTool(.pen, color: ink.uiColor, width: thickness.width)
        case .pencil:
            return PKInkingTool(.pencil, color: ink.uiColor, width: thickness.width * 1.6)
        case .marker:
            return PKInkingTool(.marker, color: ink.uiColor, width: thickness.width * 5)
        case .eraser:
            return PKEraserTool(.bitmap)
        case .lasso:
            return PKLassoTool()
        }
    }
}

enum SwipeDirection {
    case forward, backward
}
