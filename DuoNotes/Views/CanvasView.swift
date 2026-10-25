import PencilKit
import SwiftUI

/// A transparent PencilKit canvas for one page.
///
/// With `fingerDraws` off, only Apple Pencil writes. A finger drag on ink
/// picks up that word or doodle and moves it. A finger swipe on blank paper
/// turns the page.
struct CanvasView: UIViewRepresentable {
    var drawingData: Data
    var scale: CGFloat
    var tool: ToolState
    var fingerDraws: Bool
    var onChange: (Data) -> Void
    var onSwipe: (SwipeDirection) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // Keep ink colours true. PencilKit inverts them in dark mode otherwise.
        canvas.overrideUserInterfaceStyle = .light
        canvas.isScrollEnabled = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false

        // Load the drawing before attaching the delegate so loading isn't recorded as an edit.
        canvas.drawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()
        context.coordinator.loadedData = drawingData
        canvas.delegate = context.coordinator

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pan.maximumNumberOfTouches = 1
        canvas.addGestureRecognizer(pan)

        context.coordinator.canvas = canvas
        context.coordinator.fingerPan = pan
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        // Undo, redo or another device changed the drawing.
        if drawingData != coordinator.loadedData {
            coordinator.isApplyingExternalChange = true
            canvas.drawing = (try? PKDrawing(data: drawingData)) ?? PKDrawing()
            coordinator.isApplyingExternalChange = false
            coordinator.loadedData = drawingData
        }

        if coordinator.appliedTool != tool {
            canvas.tool = tool.pkTool
            coordinator.appliedTool = tool
        }

        canvas.drawingPolicy = fingerDraws ? .anyInput : .pencilOnly
        coordinator.fingerPan?.isEnabled = !fingerDraws

        // Zoom the canvas so logical page coordinates fill the view exactly.
        if abs(canvas.zoomScale - scale) > 0.0001 || canvas.minimumZoomScale != scale {
            canvas.minimumZoomScale = 0.01
            canvas.maximumZoomScale = 100
            canvas.zoomScale = scale
            canvas.minimumZoomScale = scale
            canvas.maximumZoomScale = scale
        }
        canvas.contentSize = CGSize(width: PaperMetrics.size.width * scale, height: PaperMetrics.size.height * scale)
        canvas.contentOffset = .zero
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasView
        weak var canvas: PKCanvasView?
        weak var fingerPan: UIPanGestureRecognizer?
        var loadedData = Data()
        var appliedTool: ToolState?
        var isApplyingExternalChange = false

        private var isMoving = false
        private var grabbed: [Int] = []
        private var originalStrokes: [PKStroke] = []
        private var grabStart: CGPoint = .zero

        init(_ parent: CanvasView) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingExternalChange, !isMoving else { return }
            commit(canvasView.drawing)
        }

        private func commit(_ drawing: PKDrawing) {
            let data = drawing.dataRepresentation()
            loadedData = data
            parent.onChange(data)
        }

        /// Converts a point in the canvas view to page coordinates.
        private func pagePoint(_ point: CGPoint, in canvas: PKCanvasView) -> CGPoint {
            CGPoint(x: point.x / canvas.zoomScale, y: point.y / canvas.zoomScale)
        }

        @objc func handlePan(_ pan: UIPanGestureRecognizer) {
            guard let canvas else { return }
            let point = pagePoint(pan.location(in: canvas), in: canvas)

            switch pan.state {
            case .began:
                let strokes = canvas.drawing.strokes
                grabbed = StrokeGrabber.cluster(at: point, in: strokes)
                originalStrokes = strokes
                grabStart = point
                isMoving = !grabbed.isEmpty
                if isMoving {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

            case .changed:
                guard isMoving else { return }
                let shift = CGAffineTransform(translationX: point.x - grabStart.x, y: point.y - grabStart.y)
                var strokes = originalStrokes
                for index in grabbed {
                    strokes[index].transform = originalStrokes[index].transform.concatenating(shift)
                }
                canvas.drawing = PKDrawing(strokes: strokes)

            case .ended, .cancelled, .failed:
                if isMoving {
                    isMoving = false
                    commit(canvas.drawing)
                } else if pan.state == .ended {
                    let travel = pan.translation(in: canvas)
                    if abs(travel.x) > 60, abs(travel.x) > abs(travel.y) * 1.5 {
                        parent.onSwipe(travel.x < 0 ? .forward : .backward)
                    }
                }
                grabbed = []
                originalStrokes = []

            default:
                break
            }
        }
    }
}

/// Finds the ink under a finger and everything joined to it, roughly one word or doodle.
enum StrokeGrabber {
    static func cluster(at point: CGPoint, in strokes: [PKStroke]) -> [Int] {
        // Topmost stroke wins.
        guard let hit = strokes.indices.reversed().first(where: { touches(strokes[$0], point) }) else { return [] }

        // Letters in a word sit close side by side. Lines of text are further apart
        // vertically, so the join gap is wider horizontally than vertically.
        var picked: Set<Int> = [hit]
        var frontier = [hit]
        while let current = frontier.popLast() {
            let reach = strokes[current].renderBounds.insetBy(dx: -12, dy: -4)
            for index in strokes.indices where !picked.contains(index) && strokes[index].renderBounds.intersects(reach) {
                picked.insert(index)
                frontier.append(index)
            }
        }
        return picked.sorted()
    }

    private static func touches(_ stroke: PKStroke, _ point: CGPoint, radius: CGFloat = 16) -> Bool {
        guard stroke.renderBounds.insetBy(dx: -radius, dy: -radius).contains(point) else { return false }
        for sample in stroke.path.interpolatedPoints(by: .distance(4)) {
            let location = sample.location.applying(stroke.transform)
            let reach = radius + sample.size.width / 2
            if hypot(location.x - point.x, location.y - point.y) <= reach {
                return true
            }
        }
        return false
    }
}
