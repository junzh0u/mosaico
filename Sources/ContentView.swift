import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var pickerItem: PhotosPickerItem?
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    ImageEditorView(image: Binding(
                        get: { image },
                        set: { self.image = $0 }
                    ))
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
                    }
                }
            }
        }
    }
}
