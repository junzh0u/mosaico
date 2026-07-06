import SwiftUI

struct ImageEditorView: View {
    let image: UIImage  // normalized original, never mutated

    private enum DragMode {
        case drawing
        case moving(index: Int, original: CGRect)
        case resizing(index: Int, anchor: CGPoint, original: CGRect)
    }

    @State private var rects: [CGRect] = []  // image pixel coordinates
    @State private var rendered: UIImage?
    @State private var undoStack: [[CGRect]] = []
    @State private var redoStack: [[CGRect]] = []
    @State private var dragStart: CGPoint?
    @State private var dragMode: DragMode?
    @State private var draftRect: CGRect?  // view coordinates, while drawing
    @State private var containerSize: CGSize = .zero
    @State private var saveMessage: String?
    @State private var style: MosaicStyle = .square
    @State private var tileFraction: CGFloat = 0.02
    @State private var candidates: [CGRect] = []  // detected text, image pixel coords
    @State private var detecting = false
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var pinchActive = false
    @State private var pinchStart: (zoom: CGFloat, offset: CGPoint, centroid: CGPoint)?
    @State private var dragCancelled = false  // a pinch interrupted this drag

    private let maxUndoSteps = 50
    private let handleHitRadius: CGFloat = 22
    private let minBoxSide: CGFloat = 10  // view points
    private let maxZoom: CGFloat = 8

    var body: some View {
        VStack {
            GeometryReader { geo in
                ZStack {
                    Image(uiImage: rendered ?? image)
                        .resizable()
                        .frame(width: image.size.width * displayScale,
                               height: image.size.height * displayScale)
                        .position(x: image.size.width * displayScale / 2 + displayOffset.x,
                                  y: image.size.height * displayScale / 2 + displayOffset.y)
                }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlay { decorations.allowsHitTesting(false) }
                    .overlay { removeButtons }
                    .clipped()
                    .contentShape(Rectangle())
                    .background {
                        PinchGestureLayer(onChanged: pinchChanged, onEnded: pinchEnded)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if pinchActive {
                                    cancelActiveDrag()
                                    return
                                }
                                if dragCancelled { return }
                                if dragStart == nil {
                                    dragStart = value.startLocation
                                    dragMode = hitTest(value.startLocation)
                                }
                                switch dragMode {
                                case .resizing(let i, let anchor, _):
                                    let p = clampToImage(imagePoint(fromView: value.location))
                                    rects[i] = CGRect(from: anchor, to: p)
                                case .moving(let i, let original):
                                    let scale = displayScale
                                    rects[i] = original.offsetBy(
                                        dx: (value.location.x - value.startLocation.x) / scale,
                                        dy: (value.location.y - value.startLocation.y) / scale)
                                case .drawing, nil:
                                    draftRect = CGRect(from: dragStart!, to: value.location)
                                }
                            }
                            .onEnded { _ in
                                defer {
                                    dragStart = nil
                                    dragMode = nil
                                    draftRect = nil
                                    dragCancelled = false
                                }
                                guard !dragCancelled else { return }
                                switch dragMode {
                                case .moving(let i, let original),
                                     .resizing(let i, _, let original):
                                    let changed = rects[i]
                                    let tooSmall = changed.width * displayScale < minBoxSide
                                        || changed.height * displayScale < minBoxSide
                                    rects[i] = original  // commit() snapshots pre-edit state
                                    guard changed != original, !tooSmall else { return }
                                    var newRects = rects
                                    newRects[i] = changed
                                    commit(newRects)
                                case .drawing, nil:
                                    guard let draft = draftRect else { return }
                                    if draft.width < minBoxSide, draft.height < minBoxSide {
                                        // a tap: select a detected text candidate
                                        if let tap = dragStart,
                                           let idx = candidates.firstIndex(where: {
                                               viewRect(from: $0).contains(tap)
                                           }) {
                                            let chosen = candidates.remove(at: idx)
                                            commit(rects + [chosen])
                                        }
                                        return
                                    }
                                    guard draft.width >= minBoxSide,
                                          draft.height >= minBoxSide,
                                          let pixelRect = imagePixelRect(from: draft)
                                    else { return }
                                    commit(rects + [pixelRect])
                                }
                            }
                    )
                    .onAppear { containerSize = geo.size }
                    .onChange(of: geo.size) { containerSize = geo.size }
            }

            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "circle.grid.2x2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $tileFraction, in: 0.008...0.08) { editing in
                        if !editing { rerender() }
                    }
                    Image(systemName: "circle.grid.2x2")
                        .foregroundStyle(.secondary)
                }
                Picker("Style", selection: $style) {
                    ForEach(MosaicStyle.allCases) { style in
                        Text(style.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Button { undo() } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)
                    .disabled(undoStack.isEmpty)
                    Button { redo() } label: {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .buttonStyle(.bordered)
                    .disabled(redoStack.isEmpty)
                    // stateful: prominent while candidates are on screen
                    if candidates.isEmpty {
                        Button { detectText() } label: {
                            if detecting {
                                ProgressView()
                            } else {
                                Image(systemName: "text.viewfinder")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(detecting)
                    } else {
                        Button { detectText() } label: {
                            Image(systemName: "text.viewfinder")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(rects.isEmpty)
                }
            }
            .padding()
            .onChange(of: style) { rerender() }
        }
        .alert(saveMessage ?? "", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("OK") {}
        }
    }

    // MARK: - Overlay content

    @ViewBuilder private var decorations: some View {
        ForEach(rects.indices, id: \.self) { i in
            let rect = viewRect(from: rects[i])
            Path { $0.addRect(rect) }.stroke(.yellow, lineWidth: 2)
            ForEach(Array(corners(of: rect).enumerated()), id: \.offset) { _, corner in
                Circle()
                    .fill(.white)
                    .overlay(Circle().stroke(.yellow, lineWidth: 2))
                    .frame(width: 12, height: 12)
                    .position(corner)
            }
        }
        ForEach(candidates.indices, id: \.self) { i in
            let rect = viewRect(from: candidates[i])
            Path { $0.addRect(rect) }.fill(.cyan.opacity(0.12))
            Path { $0.addRect(rect) }
                .stroke(.cyan, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
        if let rect = draftRect {
            Path { $0.addRect(rect) }.fill(.yellow.opacity(0.2))
            Path { $0.addRect(rect) }.stroke(.yellow, lineWidth: 2)
        }
    }

    @ViewBuilder private var removeButtons: some View {
        ForEach(rects.indices, id: \.self) { i in
            let rect = viewRect(from: rects[i])
            let position = CGPoint(x: rect.maxX + 16, y: rect.minY - 16)
            // .clipped() hides but doesn't disable overflowing views — skip
            // badges panned off screen so they can't be tapped invisibly
            if CGRect(origin: .zero, size: containerSize).contains(position) {
                Button { remove(i) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .position(position)
            }
        }
    }

    // MARK: - Hit testing

    private func corners(of rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.minX, y: rect.maxY),
         CGPoint(x: rect.maxX, y: rect.maxY)]
    }

    private func hitTest(_ point: CGPoint) -> DragMode {
        // Corner handles first (topmost box wins), then box interiors
        for i in rects.indices.reversed() {
            let viewCorners = corners(of: viewRect(from: rects[i]))
            for (j, corner) in viewCorners.enumerated()
            where hypot(point.x - corner.x, point.y - corner.y) <= handleHitRadius {
                let opposite = viewCorners[3 - j]
                return .resizing(index: i,
                                 anchor: clampToImage(imagePoint(fromView: opposite)),
                                 original: rects[i])
            }
        }
        for i in rects.indices.reversed()
        where viewRect(from: rects[i]).contains(point) {
            return .moving(index: i, original: rects[i])
        }
        return .drawing
    }

    // MARK: - View <-> image coordinate mapping (aspect-fit + zoom/pan)

    /// Points per image pixel when aspect-fit into the container (zoom 1)
    private var fitScale: CGFloat {
        min(containerSize.width / image.size.width,
            containerSize.height / image.size.height)
    }

    private var displayScale: CGFloat { fitScale * zoom }

    /// View coordinate of image pixel (0,0). Pan is clamped so an axis the
    /// image overflows never shows a gap; an axis it fits stays centered.
    private var displayOffset: CGPoint {
        CGPoint(x: offsetComponent(container: containerSize.width,
                                   content: image.size.width * displayScale,
                                   pan: pan.width),
                y: offsetComponent(container: containerSize.height,
                                   content: image.size.height * displayScale,
                                   pan: pan.height))
    }

    private func offsetComponent(container: CGFloat, content: CGFloat,
                                 pan: CGFloat) -> CGFloat {
        let centered = (container - content) / 2
        guard content > container else { return centered }
        return min(0, max(container - content, centered + pan))
    }

    private func clampedPan(forOffset offset: CGPoint, zoom: CGFloat) -> CGSize {
        let scale = fitScale * zoom
        return CGSize(width: panComponent(container: containerSize.width,
                                          content: image.size.width * scale,
                                          offset: offset.x),
                      height: panComponent(container: containerSize.height,
                                           content: image.size.height * scale,
                                           offset: offset.y))
    }

    private func panComponent(container: CGFloat, content: CGFloat,
                              offset: CGFloat) -> CGFloat {
        guard content > container else { return 0 }
        let half = (content - container) / 2
        return min(half, max(-half, offset - (container - content) / 2))
    }

    private func viewRect(from pixelRect: CGRect) -> CGRect {
        CGRect(x: pixelRect.minX * displayScale + displayOffset.x,
               y: pixelRect.minY * displayScale + displayOffset.y,
               width: pixelRect.width * displayScale,
               height: pixelRect.height * displayScale)
    }

    private func imagePoint(fromView p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - displayOffset.x) / displayScale,
                y: (p.y - displayOffset.y) / displayScale)
    }

    private func clampToImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), image.size.width),
                y: min(max(p.y, 0), image.size.height))
    }

    private func imagePixelRect(from viewRect: CGRect) -> CGRect? {
        let rect = CGRect(x: (viewRect.minX - displayOffset.x) / displayScale,
                          y: (viewRect.minY - displayOffset.y) / displayScale,
                          width: viewRect.width / displayScale,
                          height: viewRect.height / displayScale)
            .intersection(CGRect(origin: .zero, size: image.size))
        return rect.isEmpty ? nil : rect
    }

    // MARK: - Zoom

    private func pinchChanged(scale: CGFloat, centroid: CGPoint) {
        pinchActive = true
        let start = pinchStart ?? (zoom, displayOffset, centroid)
        pinchStart = start
        let newZoom = min(max(start.zoom * scale, 1), maxZoom)
        // keep the image point under the pinch centroid pinned to it, so the
        // gesture both zooms about the fingers and pans as they move
        let k = newZoom / start.zoom
        let offset = CGPoint(x: centroid.x - (start.centroid.x - start.offset.x) * k,
                             y: centroid.y - (start.centroid.y - start.offset.y) * k)
        zoom = newZoom
        pan = clampedPan(forOffset: offset, zoom: newZoom)
    }

    private func pinchEnded() {
        pinchActive = false
        pinchStart = nil
        if zoom == 1 { pan = .zero }
    }

    private func cancelActiveDrag() {
        switch dragMode {
        case .moving(let i, let original), .resizing(let i, _, let original):
            rects[i] = original
        case .drawing, nil:
            break
        }
        draftRect = nil
        dragMode = nil
        dragStart = nil
        dragCancelled = true
    }

    // MARK: - Edits

    private func commit(_ newRects: [CGRect]) {
        undoStack.append(rects)
        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        rects = newRects
        rerender()
    }

    private func remove(_ i: Int) {
        var newRects = rects
        newRects.remove(at: i)
        commit(newRects)
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(rects)
        rects = previous
        rerender()
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(rects)
        rects = next
        rerender()
    }

    /// Toggles smart text detection: shows recognized text regions as
    /// dashed candidates; tapping one masks it.
    private func detectText() {
        if !candidates.isEmpty {
            candidates = []
            return
        }
        detecting = true
        Task {
            let boxes = await TextDetector.detectTextRects(in: image)
            // skip regions already fully covered by an existing mosaic box
            candidates = boxes.filter { box in
                !rects.contains { $0.contains(box) }
            }
            detecting = false
            if candidates.isEmpty {
                saveMessage = "No text found in this photo"
            }
        }
    }

    private func rerender() {
        rendered = MosaicProcessor.applyMosaics(to: image, in: rects,
                                                style: style,
                                                tileFraction: tileFraction)
    }

    private func save() {
        MosaicProcessor.save(rendered ?? image) { ok in
            saveMessage = ok
                ? "Saved to Photos"
                : "Save failed — check Photos permission in Settings"
        }
    }
}

extension CGRect {
    init(from a: CGPoint, to b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y),
                  width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}

/// Invisible layer that reports two-finger pinches. The recognizer is
/// attached to the window — not this view — so single-finger touches still
/// reach the SwiftUI drag gesture; pinches whose centroid starts outside
/// this view's bounds are ignored. Centroids are reported in this view's
/// coordinate space, which matches the editor container.
private struct PinchGestureLayer: UIViewRepresentable {
    let onChanged: (CGFloat, CGPoint) -> Void  // (cumulative scale, centroid)
    let onEnded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WindowObservingView {
        let view = WindowObservingView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        context.coordinator.view = view
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateUIView(_ uiView: WindowObservingView, context: Context) {
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    static func dismantleUIView(_ uiView: WindowObservingView, coordinator: Coordinator) {
        coordinator.attach(to: nil)
    }

    final class WindowObservingView: UIView {
        var onWindowChange: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onWindowChange?(window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var view: UIView?
        var onChanged: ((CGFloat, CGPoint) -> Void)?
        var onEnded: (() -> Void)?
        private var recognizer: UIPinchGestureRecognizer?
        private var tracking = false

        func attach(to window: UIWindow?) {
            if let recognizer {
                recognizer.view?.removeGestureRecognizer(recognizer)
                self.recognizer = nil
            }
            guard let window else { return }
            let pinch = UIPinchGestureRecognizer(target: self,
                                                 action: #selector(handlePinch))
            pinch.cancelsTouchesInView = false
            pinch.delegate = self
            window.addGestureRecognizer(pinch)
            recognizer = pinch
        }

        @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let view else { return }
            switch gesture.state {
            case .began:
                tracking = view.bounds.contains(gesture.location(in: view))
                fallthrough
            case .changed:
                if tracking {
                    onChanged?(gesture.scale, gesture.location(in: view))
                }
            case .ended, .cancelled, .failed:
                if tracking { onEnded?() }
                tracking = false
            default:
                break
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
