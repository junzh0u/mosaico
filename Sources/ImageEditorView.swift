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

    private let maxUndoSteps = 50
    private let handleHitRadius: CGFloat = 22
    private let minBoxSide: CGFloat = 10  // view points

    var body: some View {
        VStack {
            GeometryReader { geo in
                Image(uiImage: rendered ?? image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlay { decorations.allowsHitTesting(false) }
                    .overlay { removeButtons }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStart == nil {
                                    dragStart = value.startLocation
                                    dragMode = hitTest(value.startLocation)
                                }
                                switch dragMode {
                                case .resizing(let i, let anchor, _):
                                    let p = clampToImage(imagePoint(fromView: value.location))
                                    rects[i] = CGRect(from: anchor, to: p)
                                case .moving(let i, let original):
                                    let scale = fitScale
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
                                }
                                switch dragMode {
                                case .moving(let i, let original),
                                     .resizing(let i, _, let original):
                                    let changed = rects[i]
                                    let tooSmall = changed.width * fitScale < minBoxSide
                                        || changed.height * fitScale < minBoxSide
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
            Button { remove(i) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .position(x: rect.maxX + 16, y: rect.minY - 16)
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

    // MARK: - View <-> image coordinate mapping (aspect-fit letterboxing)

    /// Points per image pixel when aspect-fit into the container
    private var fitScale: CGFloat {
        min(containerSize.width / image.size.width,
            containerSize.height / image.size.height)
    }

    private var fitOffset: CGPoint {
        CGPoint(x: (containerSize.width - image.size.width * fitScale) / 2,
                y: (containerSize.height - image.size.height * fitScale) / 2)
    }

    private func viewRect(from pixelRect: CGRect) -> CGRect {
        CGRect(x: pixelRect.minX * fitScale + fitOffset.x,
               y: pixelRect.minY * fitScale + fitOffset.y,
               width: pixelRect.width * fitScale,
               height: pixelRect.height * fitScale)
    }

    private func imagePoint(fromView p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - fitOffset.x) / fitScale,
                y: (p.y - fitOffset.y) / fitScale)
    }

    private func clampToImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), image.size.width),
                y: min(max(p.y, 0), image.size.height))
    }

    private func imagePixelRect(from viewRect: CGRect) -> CGRect? {
        let rect = CGRect(x: (viewRect.minX - fitOffset.x) / fitScale,
                          y: (viewRect.minY - fitOffset.y) / fitScale,
                          width: viewRect.width / fitScale,
                          height: viewRect.height / fitScale)
            .intersection(CGRect(origin: .zero, size: image.size))
        return rect.isEmpty ? nil : rect
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
