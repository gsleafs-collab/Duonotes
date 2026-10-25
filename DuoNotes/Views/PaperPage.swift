import SwiftUI

enum PageSide {
    case left, right, single
}

/// One sheet of lined paper with a writable canvas on top.
struct PaperPage: View {
    let page: Page
    let pageNumber: Int
    let side: PageSide
    let tool: ToolState
    let fingerDraws: Bool
    var onChange: (Data) -> Void
    var onSwipe: (SwipeDirection) -> Void

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / PaperMetrics.size.width
            ZStack {
                LinedPaper()
                CanvasView(
                    drawingData: page.drawing,
                    scale: scale,
                    tool: tool,
                    fingerDraws: fingerDraws,
                    onChange: onChange,
                    onSwipe: onSwipe
                )
            }
            .overlay(alignment: side == .left ? .bottomLeading : .bottomTrailing) {
                Text("\(pageNumber)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color(white: 0.55))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .aspectRatio(PaperMetrics.size, contentMode: .fit)
    }
}

/// Composition book paper: blue rules and a red margin.
struct LinedPaper: View {
    var body: some View {
        Canvas { context, size in
            let scale = size.width / PaperMetrics.size.width
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.99, green: 0.98, blue: 0.95)))

            var rules = Path()
            var y = PaperMetrics.topMargin
            while y < PaperMetrics.size.height - PaperMetrics.lineSpacing / 2 {
                rules.move(to: CGPoint(x: 0, y: y * scale))
                rules.addLine(to: CGPoint(x: size.width, y: y * scale))
                y += PaperMetrics.lineSpacing
            }
            context.stroke(rules, with: .color(Color(red: 0.55, green: 0.72, blue: 0.90)), lineWidth: max(0.5, scale))

            var margin = Path()
            let x = PaperMetrics.leftMargin * scale
            margin.move(to: CGPoint(x: x, y: 0))
            margin.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(margin, with: .color(Color(red: 0.90, green: 0.45, blue: 0.50)), lineWidth: max(0.75, scale * 1.2))
        }
        .allowsHitTesting(false)
    }
}
