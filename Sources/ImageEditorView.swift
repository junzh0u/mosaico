import SwiftUI

struct ImageEditorView: View {
    let image: UIImage  // normalized original, never mutated

    @State private var rects: [CGRect] = []  // image pixel coordinates
    @State private var rendered: UIImage?
    @State private var undoStack: [[CGRect]] = []
    @State private var redoStack: [[CGRect]] = []
    @State private var dragStart: CGPoint?
    @State private var draftRect: CGRect?  // view coordinates, while drawing
    @State private var movingIndex: Int?
    @State private var movingOriginal: CGRect?  // rect at move start, image space
    @State private var containerSize: CGSize = .zero
    @State private var saveMessage: String?

    private let maxUndoSteps = 50

    var body: some View {
        VStack {
            GeometryReader { geo in
                Image(uiImage: rendered ?? image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlay {
                        ForEach(rects.indices, id: \.self) { i in
                            let rect = viewRect(from: rects[i])
                            Path { $0.addRect(rect) }.stroke(.yellow, lineWidth: 2)
                        }
                        if let rect = draftRect {
                            Path { $0.addRect(rect) }.fill(.yellow.opacity(0.2))
                            Path { $0.addRect(rect) }.stroke(.yellow, lineWidth: 2)
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStart == nil {
                                    dragStart = value.startLocation
                                    // Starting inside an existing box moves it
                                    // (topmost first); otherwise draw a new one
                                    movingIndex = rects.indices.reversed().first {
                                        viewRect(from: rects[$0]).contains(value.startLocation)
                                    }
                                    movingOriginal = movingIndex.map { rects[$0] }
                                }
                                if let i = movingIndex, let original = movingOriginal {
                                    let scale = fitScale
                                    rects[i] = original.offsetBy(
                                        dx: (value.location.x - value.startLocation.x) / scale,
                                        dy: (value.location.y - value.startLocation.y) / scale)
                                } else {
                                    draftRect = CGRect(from: dragStart!, to: value.location)
                                }
                            }
                            .onEnded { _ in
                                defer {
                                    dragStart = nil
                                    draftRect = nil
                                    movingIndex = nil
                                    movingOriginal = nil
                                }
                                if let i = movingIndex, let original = movingOriginal {
                                    let moved = rects[i]
                                    guard moved != original else { return }
                                    rects[i] = original  // commit() snapshots pre-move state
                                    var newRects = rects
                                    newRects[i] = moved
                                    commit(newRects)
                                } else if let draft = draftRect,
                                          let pixelRect = imagePixelRect(from: draft) {
                                    commit(rects + [pixelRect])
                                }
                            }
                    )
                    .onAppear { containerSize = geo.size }
                    .onChange(of: geo.size) { containerSize = geo.size }
            }

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
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(rects.isEmpty)
            }
            .padding()
        }
        .alert(saveMessage ?? "", isPresented: Binding(
            get: { saveMessage != nil },
            set: { if !$0 { saveMessage = nil } }
        )) {
            Button("OK") {}
        }
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

    private func rerender() {
        rendered = MosaicProcessor.applyMosaics(to: image, in: rects)
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
