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
                pager.setViewControllers(pages, direction: direction, animated: true)
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
            guard touch.type == .direct, let view = pager?.view else { return false }
            let x = touch.location(in: view).x
            return x < BookPager.turnEdge || x > view.bounds.width - BookPager.turnEdge
        }
    }
}

/// One sheet of paper: ruled lines underneath, a PencilKit canvas on top.
final class PageViewController: UIViewController, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
    let index: Int
    let pageID: UUID
    var onDrawingChange: ((UUID, Data) -> Void)?

    private let paper = LinedPaperView()
    private let canvas = PKCanvasView()
    private let numberLabel = UILabel()
    private let movePan = UIPanGestureRecognizer()
    private var loadedData: Data
    private var isApplyingExternalChange = false
    private var appliedPen: PenSettings?
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
        canvas.delegate = self
        view.addSubview(canvas)

        movePan.addTarget(self, action: #selector(handleMove(_:)))
        movePan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        movePan.maximumNumberOfTouches = 1
        movePan.delegate = self
        canvas.addGestureRecognizer(movePan)

        numberLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        numberLabel.text = "\(index + 1)"
        view.addSubview(numberLabel)
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

        // Page number in the outer bottom corner, clear of the rounded screen corners.
        numberLabel.sizeToFit()
        let inset: CGFloat = 30
        let x = side == .left ? inset : bounds.width - numberLabel.bounds.width - inset
        numberLabel.frame.origin = CGPoint(x: x, y: bounds.height - numberLabel.bounds.height - inset)
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
        numberLabel.textColor = PaperPalette(dark: dark).number
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
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        guard !isApplyingExternalChange, !isMoving else { return }
        commit()
    }

    private func commit() {
        let data = canvas.drawing.dataRepresentation()
        loadedData = data
        onDrawingChange?(pageID, data)
    }

    // MARK: Moving ink with a finger

    /// Leaves the outer edge free for turning the page.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
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
        let shade = UIColor.black.withAlphaComponent(isDark ? 0.5 : 0.2).cgColor
        let clear = UIColor.black.withAlphaComponent(0).cgColor
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [shade, clear] as CFArray,
                                        locations: [0, 1]) else { return }
        let width: CGFloat = 30
        if spineEdge == .left {
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: 0), options: [])
        } else {
            context.drawLinearGradient(gradient, start: CGPoint(x: bounds.width, y: 0),
                                       end: CGPoint(x: bounds.width - width, y: 0), options: [])
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
