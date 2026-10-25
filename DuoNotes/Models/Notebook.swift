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
    var createdAt = Date()
    var updatedAt = Date()
    var pages: [Page] = [Page(), Page()]
}

/// Logical size of one sheet of paper. Drawings are stored in these
/// coordinates so writing lines up with the rules on any screen size.
/// Sized for the iPhone Duo: about 1:1 on the outer screen, larger when
/// unfolded. 34 pt rules come out near college ruled on the Duo's displays.
enum PaperMetrics {
    static let size = CGSize(width: 440, height: 620)
    static let lineSpacing: CGFloat = 34
    static let topMargin: CGFloat = 80
    static let leftMargin: CGFloat = 52
}
