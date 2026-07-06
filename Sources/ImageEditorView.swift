import SwiftUI

struct ImageEditorView: View {
    @Binding var image: UIImage
    @State private var dragStart: CGPoint?
    @State private var selectionRect: CGRect?  // view coordinates
    @State private var containerSize: CGSize = .zero
    @State private var saveMessage: String?
    @State private var undoStack: [UIImage] = []
    @State private var redoStack: [UIImage] = []

    private let maxUndoSteps = 10

    var body: some View {
        VStack {
            GeometryReader { geo in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .overlay {
                        if let rect = selectionRect {
                            Path { $0.addRect(rect) }.fill(.yellow.opacity(0.2))
                            Path { $0.addRect(rect) }.stroke(.yellow, lineWidth: 2)
                        }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let start = dragStart ?? value.startLocation
                                dragStart = start
                                selectionRect = CGRect(from: start, to: value.location)
                            }
                            .onEnded { _ in dragStart = nil }
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
                Button("Apply Mosaic") { applyMosaic() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectionRect == nil)
                Button("Save") { save() }
                    .buttonStyle(.bordered)
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

    /// Maps a rect in view coordinates to image pixel coordinates,
    /// accounting for aspect-fit letterboxing.
    private func imagePixelRect(from viewRect: CGRect) -> CGRect? {
        let imgSize = image.size  // true pixel size thanks to normalized()
        let scale = min(containerSize.width / imgSize.width,
                        containerSize.height / imgSize.height)
        let displayed = CGSize(width: imgSize.width * scale,
                               height: imgSize.height * scale)
        let offsetX = (containerSize.width - displayed.width) / 2
        let offsetY = (containerSize.height - displayed.height) / 2

        let rect = CGRect(x: (viewRect.minX - offsetX) / scale,
                          y: (viewRect.minY - offsetY) / scale,
                          width: viewRect.width / scale,
                          height: viewRect.height / scale)
            .intersection(CGRect(origin: .zero, size: imgSize))
        return rect.isEmpty ? nil : rect
    }

    private func applyMosaic() {
        guard let viewRect = selectionRect,
              let pixelRect = imagePixelRect(from: viewRect),
              let result = MosaicProcessor.applyMosaic(to: image, in: pixelRect)
        else { return }
        undoStack.append(image)
        if undoStack.count > maxUndoSteps {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        image = result
        selectionRect = nil
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(image)
        image = previous
        selectionRect = nil
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(image)
        image = next
        selectionRect = nil
    }

    private func save() {
        MosaicProcessor.save(image) { ok in
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
