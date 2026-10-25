import SwiftUI

/// The tint of a notebook's marbled cover.
enum CoverStyle: String, Codable, CaseIterable, Identifiable {
    case classic, navy, crimson, forest, plum

    var id: String { rawValue }
    var name: String { rawValue.capitalized }

    var ink: Color {
        switch self {
        case .classic: return Color(white: 0.08)
        case .navy: return Color(red: 0.07, green: 0.13, blue: 0.35)
        case .crimson: return Color(red: 0.45, green: 0.05, blue: 0.08)
        case .forest: return Color(red: 0.05, green: 0.27, blue: 0.15)
        case .plum: return Color(red: 0.30, green: 0.08, blue: 0.35)
        }
    }
}

struct Page: Identifiable, Codable, Hashable {
    var id = UUID()
    /// PencilKit drawing data. Empty for a blank page.
    var drawing = Data()
}

struct Notebook: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var cover: CoverStyle
    /// A colour picked from the spectrum. Overrides `cover` when set.
    var customCover: RGBA?
    var createdAt = Date()
    var updatedAt = Date()
    var pages: [Page] = [Page(), Page()]

    var coverInk: Color { customCover?.color ?? cover.ink }
}

/// Page layout in logical points. Drawings are stored in these coordinates,
/// so writing stays on its line whether the page is shown folded, unfolded
/// or as half of a spread. The page width is fixed and the height follows
/// the screen, which on the iPhone Duo is close to 1.42 times the width in
/// every layout.
enum PaperMetrics {
    static let width: CGFloat = 440
    static let lineSpacing: CGFloat = 28
    static let topMargin: CGFloat = 76
    static let leftMargin: CGFloat = 52
    /// Typical page height on the iPhone Duo, used for thumbnails.
    static let typicalHeight: CGFloat = 625
}

/// Paper colours for light and dark mode.
struct PaperPalette {
    let paper: UIColor
    let rule: UIColor
    let margin: UIColor
    let number: UIColor

    init(dark: Bool) {
        if dark {
            paper = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
            rule = UIColor(red: 0.25, green: 0.34, blue: 0.46, alpha: 1)
            margin = UIColor(red: 0.52, green: 0.25, blue: 0.29, alpha: 1)
            number = UIColor(white: 0.5, alpha: 1)
        } else {
            paper = UIColor(red: 0.99, green: 0.98, blue: 0.95, alpha: 1)
            rule = UIColor(red: 0.62, green: 0.76, blue: 0.92, alpha: 1)
            margin = UIColor(red: 0.91, green: 0.50, blue: 0.55, alpha: 1)
            number = UIColor(white: 0.55, alpha: 1)
        }
    }
}
