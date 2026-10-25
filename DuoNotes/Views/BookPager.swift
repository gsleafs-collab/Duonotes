import PencilKit
import SwiftUI
import UIKit

enum PageSide {
    case left, right, single
}

/// The open notebook, built on UIPageViewController's page curl.
///
/// Portrait shows one page. Landscape shows two with the spine in the middle.
/// Drag from the outer edge with a finger to flip. Flipping past the last
/// page adds fresh paper.
struct BookPager: UIViewControllerRepresentable {
    let store: NotebookStore
    let notebook: Notebook
    let spread: Bool
    let pen: PenSettings
    let dark: Bool
    @Binding var currentPage: Int
    /// Called when a page number is tapped.
    var onShowPages: () -> Void

    /// Width of the strip along the outer edges where a finger starts a page turn.
    static let turnEdge: CGFloat = 44

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let spine: UIPageViewController.SpineLocation = spread ? .mid : .min
        let pager = UIPageViewController(
            transitionStyle: .pageCurl,
            navigationOrientation: .horizontal,
            options: [.spineLocation: NSNumber(value: spine.rawValue)]
        )
        pager.isDoubleSided = spread
        pager.dataSource = context.coordinator
        pager.delegate = context.coordinator
        pager.view.backgroundColor = PaperPalette(dark: dark).paper
        for recognizer in pager.gestureRecognizers {
            recognizer.delegate = context.coordinator
        }

        let coordinator = context.coordinator
        coordinator.pager = pager
        let first = normalized(currentPage)
        coordinator.displayedFirst = first
        pager.setViewControllers(coordinator.controllers(startingAt: first), direction: .forward, animated: false)
        return pager
    }

    func updateUIViewController(_ pager: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        pager.view.backgroundColor = PaperPalette(dark: dark).paper

        // Jump to a page chosen outside the pager, such as after undo.
        let first = normalized(currentPage)
        if first != coordinator.displayedFirst, !coordinator.isTurning {
            let pages = coordinator.controllers(startingAt: first)
            if !pages.isEmpty {
                let direction: UIPageViewController.NavigationDirection = first > coordinator.displayedFirst ? .forward : .reverse
                coordinator.displayedFirst = first
                coordinator.isTurning = true
                pager.setViewControllers(pages, direction: direction, animated: true) { [weak coordinator] _ in
                    coordinator?.isTurning = false
                }
            }
        }

        for case let page as PageViewController in pager.viewControllers ?? [] {
            page.apply(pen: pen, dark: dark, side: coordinator.side(for: page.index))
            if let data = notebook.pages.first(where: { $0.id == page.pageID })?.drawing {
                page.sync(data)
            }
        }
    }

    private func normalized(_ index: Int) -> Int {
        spread ? index - index % 2 : index
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIGestureRecognizerDelegate {
        var parent: BookPager
        weak var pager: UIPageViewController?
        var displayedFirst = 0
        var isTurning = false

        init(_ parent: BookPager) {
            self.parent = parent
        }

        func side(for index: Int) -> PageSide {
            guard parent.spread else { return .single }
            return index % 2 == 0 ? .left : .right
        }

        func controllers(startingAt first: Int) -> [PageViewController] {
            let indexes = parent.spread ? [first, first + 1] : [first]
            let pages = indexes.compactMap(makePage)
            return pages.count == indexes.count ? pages : []
        }

        /// Builds the controller for a page, adding paper if the notebook runs out.
        func makePage(_ index: Int) -> PageViewController? {
            guard index >= 0, index < NotebookStore.maxPages else { return nil }
            let store = parent.store
            let notebookID = parent.notebook.id
            // Read from the store rather than `parent.notebook` so pages added
            // a moment ago during this same page turn are visible.
            store.ensurePageCount(notebookID, index + 1)
            guard let pages = store.notebook(notebookID)?.pages, index < pages.count else { return nil }

            let page = pages[index]
            let controller = PageViewController(index: index, pageID: page.id, drawing: page.drawing)
            controller.onDrawingChange = { [weak store] pageID, data in
                store?.setDrawing(data, notebook: notebookID, page: pageID)
            }
            controller.onNumberTap = { [weak self] in
                self?.parent.onShowPages()
            }
            controller.apply(pen: parent.pen, dark: parent.dark, side: side(for: index))
            return controller
        }

        // MARK: Data source

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let page = viewController as? PageViewController else { return nil }
            return makePage(page.index - 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let page = viewController as? PageViewController else { return nil }
            return makePage(page.index + 1)
        }

        // MARK: Delegate

        func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {
            isTurning = true
        }

        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            isTurning = false
            guard completed, let first = (pageViewController.viewControllers?.first as? PageViewController)?.index else { return }
            displayedFirst = first
            if parent.currentPage != first {
                parent.currentPage = first
            }
        }

        // MARK: Page turn gestures

        /// Only a finger near the outer edges turns pages, so Apple Pencil can
        /// write right up to the edge and a finger can move ink elsewhere.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard touch.type == .direct, !(touch.view is UIControl), let view = pager?.view else { return false }
            let x = touch.location(in: view).x
            return x < BookPager.turnEdge || x > view.bounds.width - BookPager.turnEdge
        }

        /// Refuses a turn with no page to land on, such as back from page one,
        /// and a second turn while one is still animating. UIPageViewController
        /// can crash in both cases.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard !isTurning, let view = pager?.view else { return false }
            let turningBack = gestureRecognizer.location(in: view).x < view.bounds.midX
            if turningBack {
                return displayedFirst > 0
            }
            return displayedFirst + (parent.spread ? 2 : 1) < NotebookStore.maxPages
        }
    }
}

/// One sheet of paper: ruled lines underneath, a PencilKit canvas on top.
final class PageViewController: UIViewController, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
    let index: Int
    let pageID: UUID
    var onDrawingChange: ((UUID, Data) -> Void)?
    var onNumberTap: (() -> Void)?

    private let paper = LinedPaperView()
    private let canvas = PKCanvasView()
    private let numberButton = UIButton(type: .system)
    private let movePan = UIPanGestureRecognizer()
    private var loadedData: Data
    private var isApplyingExternalChange = false
    private var appliedPen: PenSettings?
    /// Strokes on the page after the last save, used to spot a newly drawn stroke.
    private var strokeCount = 0
    private var side: PageSide = .single

    // Finger move state.
    private var isMoving = false
    private var grabbed: [Int] = []
    private var originalStrokes: [PKStroke] = []
    private var grabStart: CGPoint = .zero

    init(index: Int, pageID: UUID, drawing: Data) {
        self.index = index
        self.pageID = pageID
        self.loadedData = drawing
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(paper)

        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.isScrollEnabled = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        // Load before attaching the delegate so loading isn't recorded as an edit.
        canvas.drawing = (try? PKDrawing(data: loadedData)) ?? PKDrawing()
        strokeCount = canvas.drawing.strokes.count
        canvas.delegate = self
        view.addSubview(canvas)

        movePan.addTarget(self, action: #selector(handleMove(_:)))
        movePan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        movePan.maximumNumberOfTouches = 1
        movePan.delegate = self
        canvas.addGestureRecognizer(movePan)

        numberButton.setTitle("\(index + 1)", for: .normal)
        numberButton.titleLabel?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        numberButton.accessibilityLabel = "Page \(index + 1). Show all pages"
        numberButton.addAction(UIAction { [weak self] _ in self?.onNumberTap?() }, for: .touchUpInside)
        view.addSubview(numberButton)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        paper.frame = bounds
        canvas.frame = bounds

        // Zoom the canvas so the fixed page width fills the view exactly.
        let scale = bounds.width / PaperMetrics.width
        if scale > 0, abs(canvas.zoomScale - scale) > 0.0001 || canvas.minimumZoomScale != scale {
            canvas.minimumZoomScale = 0.01
            canvas.maximumZoomScale = 100
            canvas.zoomScale = scale
            canvas.minimumZoomScale = scale
            canvas.maximumZoomScale = scale
        }
        canvas.contentSize = bounds.size
        canvas.contentOffset = .zero

        // Page number centred at the bottom, away from the page turn edges.
        // The frame is larger than the text so it's easy to tap.
        let size = CGSize(width: 64, height: 40)
        numberButton.frame = CGRect(x: (bounds.width - size.width) / 2,
                                    y: bounds.height - size.height - 14,
                                    width: size.width,
                                    height: size.height)
    }

    func apply(pen: PenSettings, dark: Bool, side: PageSide) {
        loadViewIfNeeded()
        if appliedPen != pen {
            canvas.tool = pen.pkTool
            canvas.drawingPolicy = pen.fingerDraws ? .anyInput : .pencilOnly
            movePan.isEnabled = !pen.fingerDraws
            appliedPen = pen
        }
        // PencilKit flips dark ink to light on dark paper so writing stays readable.
        canvas.overrideUserInterfaceStyle = dark ? .dark : .light
        paper.isDark = dark
        paper.spineEdge = side == .left ? .right : (side == .right ? .left : nil)
        numberButton.tintColor = PaperPalette(dark: dark).number
        if self.side != side {
            self.side = side
            view.setNeedsLayout()
        }
    }

    /// Shows a drawing changed elsewhere, for example by undo.
    func sync(_ data: Data) {
        guard data != loadedData, !isMoving else { return }
        loadedData = data
        guard isViewLoaded else { return }
        isApplyingExternalChange = true
        canvas.drawing = (try? PKDrawing(data: data)) ?? PKDrawing()
        isApplyingExternalChange = false
        strokeCount = canvas.drawing.strokes.count
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isApplyingExternalChange, !isMoving else { return }
        if eraseScribble(in: canvasView.drawing) { return }
        commit()
    }

    private func commit() {
        let data = canvas.drawing.dataRepresentation()
        loadedData = data
        strokeCount = canvas.drawing.strokes.count
        onDrawingChange?(pageID, data)
    }

    /// If the stroke just drawn scribbles over writing, removes that writing and
    /// the scribble together. They're saved as one change so a single undo
    /// brings the writing back.
    private func eraseScribble(in drawing: PKDrawing) -> Bool {
        guard let pen = appliedPen, pen.scribbleToErase, pen.tool.usesInk else { return false }
        let strokes = drawing.strokes
        guard strokes.count == strokeCount + 1, let scribble = strokes.last else { return false }

        let earlier = Array(strokes.dropLast())
        let erased = ScribbleEraser.strokesErased(by: scribble, in: earlier)
        guard !erased.isEmpty else { return false }

        let kept = earlier.enumerated().filter { !erased.contains($0.offset) }.map(\.element)
        // Replace the drawing on the next turn of the run loop, after PencilKit
        // has finished handling the stroke.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isApplyingExternalChange = true
            self.canvas.drawing = PKDrawing(strokes: kept)
            self.isApplyingExternalChange = false
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            self.commit()
        }
        return true
    }

    // MARK: Moving ink with a finger

    /// Leaves the outer edge free for turning the page.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.view is UIControl { return false }
        let x = touch.location(in: view).x
        let edge = BookPager.turnEdge
        switch side {
        case .left: return x > edge
        case .right: return x < view.bounds.width - edge
        case .single: return x > edge && x < view.bounds.width - edge
        }
    }

    @objc private func handleMove(_ pan: UIPanGestureRecognizer) {
        let location = pan.location(in: canvas)
        let point = CGPoint(x: location.x / canvas.zoomScale, y: location.y / canvas.zoomScale)

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
                commit()
            }
            grabbed = []
            originalStrokes = []

        default:
            break
        }
    }
}

/// Ruled composition paper, with a soft shadow along the spine in a spread.
final class LinedPaperView: UIView {
    var isDark = false {
        didSet { if isDark != oldValue { setNeedsDisplay() } }
    }

    /// Which edge of this page touches the spine, if any.
    var spineEdge: UIRectEdge? {
        didSet { if spineEdge != oldValue { setNeedsDisplay() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .redraw
        isOpaque = true
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let palette = PaperPalette(dark: isDark)
        let scale = bounds.width / PaperMetrics.width

        palette.paper.setFill()
        context.fill(bounds)

        palette.rule.setStroke()
        context.setLineWidth(max(0.5, scale))
        let spacing = PaperMetrics.lineSpacing * scale
        var y = PaperMetrics.topMargin * scale
        while y < bounds.height - spacing / 2 {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: bounds.width, y: y))
            y += spacing
        }
        context.strokePath()

        palette.margin.setStroke()
        context.setLineWidth(max(0.75, scale * 1.2))
        let x = PaperMetrics.leftMargin * scale
        context.move(to: CGPoint(x: x, y: 0))
        context.addLine(to: CGPoint(x: x, y: bounds.height))
        context.strokePath()

        guard let spineEdge else { return }
        let shade = UIColor.black.withAlphaComponent(isDark ? 0.3 : 0.08).cgColor
        let clear = UIColor.black.withAlphaComponent(0).cgColor
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [shade, clear] as CFArray,
                                        locations: [0, 1]) else { return }
        let width: CGFloat = 22
        if spineEdge == .left {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: 0), options: [])
        } else {
            context.drawLinearGradient(gradient, start: CGPoint(x: bounds.width, y: 0),
                                       end: CGPoint(x: bounds.width - width, y: 0), options: [])
        }
    }
}

/// Spots a quick back and forth scribble drawn over writing.
enum ScribbleEraser {
    /// Indexes of the strokes a scribble crosses out. Empty if the stroke isn't
    /// a scribble or there's no writing under it.
    static func strokesErased(by scribble: PKStroke, in strokes: [PKStroke]) -> Set<Int> {
        guard isScribble(scribble) else { return [] }
        let area = scribble.renderBounds
        var erased = Set<Int>()
        for (index, stroke) in strokes.enumerated() {
            let bounds = stroke.renderBounds
            let overlap = bounds.intersection(area)
            guard !overlap.isNull, bounds.width > 0, bounds.height > 0 else { continue }
            // Erase strokes that are at least half covered by the scribble.
            if overlap.width * overlap.height >= bounds.width * bounds.height * 0.5 {
                erased.insert(index)
            }
        }
        return erased
    }

    private static func isScribble(_ stroke: PKStroke) -> Bool {
        let points = stroke.path.interpolatedPoints(by: .distance(3)).map { $0.location.applying(stroke.transform) }
        guard points.count >= 10, let duration = stroke.path.last?.timeOffset, duration > 0 else { return false }

        var length: CGFloat = 0
        for (from, to) in zip(points, points.dropFirst()) {
            length += hypot(to.x - from.x, to.y - from.y)
        }
        let bounds = stroke.renderBounds
        let span = max(bounds.width, bounds.height)
        guard span > 16 else { return false }

        // A scribble doubles back on itself many times, covers its area densely
        // and is drawn fast.
        let reversals = max(reversalCount(points.map(\.x)), reversalCount(points.map(\.y)))
        let speed = length / CGFloat(duration)
        return reversals >= 5 && length > span * 3 && speed > 120
    }

    /// Counts direction changes along one axis, ignoring wobbles under `threshold` points.
    private static func reversalCount(_ values: [CGFloat], threshold: CGFloat = 6) -> Int {
        guard var extreme = values.first else { return 0 }
        var direction: CGFloat = 0
        var reversals = 0
        for value in values.dropFirst() {
            let delta = value - extreme
            if direction == 0 {
                if abs(delta) > threshold {
                    direction = delta > 0 ? 1 : -1
                    extreme = value
                }
            } else if delta * direction > 0 {
                extreme = value
            } else if abs(delta) > threshold {
                reversals += 1
                direction = -direction
                extreme = value
            }
        }
        return reversals
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
