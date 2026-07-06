import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var photoID = UUID()

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    ImageEditorView(image: image)
                        // New identity per picked photo so editor state
                        // (selection boxes, undo history) starts fresh
                        .id(photoID)
                } else {
                    ContentUnavailableView(
                        "No Photo",
                        systemImage: "photo",
                        description: Text("Choose a photo to get started.")
                    )
                }
            }
            .toolbar {
                PhotosPicker("Choose Photo", selection: $pickerItem, matching: .images)
            }
            .onChange(of: pickerItem) {
                Task {
                    if let data = try? await pickerItem?.loadTransferable(type: Data.self),
                       let loaded = UIImage(data: data) {
                        image = loaded.normalized()
                        photoID = UUID()
                    }
                }
            }
        }
    }
}
