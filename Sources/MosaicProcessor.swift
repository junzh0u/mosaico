import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos

enum MosaicStyle: String, CaseIterable, Identifiable {
    case square = "Square"
    case polygon = "Polygon"
    var id: Self { self }
}

enum MosaicProcessor {
    private static let context = CIContext()

    /// Mosaics the given rects (in image pixel coordinates, top-left origin)
    /// and composites them over the original image. `tileFraction` is the
    /// tile size as a fraction of the longest image dimension.
    static func applyMosaics(to image: UIImage,
                             in pixelRects: [CGRect],
                             style: MosaicStyle = .polygon,
                             tileFraction: CGFloat = 0.02) -> UIImage? {
        guard !pixelRects.isEmpty else { return image }
        guard let cgImage = image.cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)

        // Tile size proportional to image dimension, never smaller than 8 px
        let tile = Float(max(max(input.extent.width, input.extent.height) * tileFraction, 8))
        let center = CGPoint(x: input.extent.midX, y: input.extent.midY)

        // Clamp edges so border tiles don't average with transparency,
        // then crop the infinite-extent output back to the image bounds
        let clamped = input.clampedToExtent()
        let filtered: CIImage?
        switch style {
        case .square:
            let filter = CIFilter.pixellate()
            filter.inputImage = clamped
            filter.scale = tile
            filter.center = center
            filtered = filter.outputImage
        case .polygon:
            let filter = CIFilter.crystallize()
            filter.inputImage = clamped
            filter.radius = tile
            filter.center = center
            filtered = filter.outputImage
        }
        guard let pixellated = filtered?.cropped(to: input.extent) else { return nil }

        var output = input
        for pixelRect in pixelRects {
            // UIKit rect (top-left origin) -> Core Image rect (bottom-left origin)
            let ciRect = CGRect(x: pixelRect.minX,
                                y: input.extent.height - pixelRect.maxY,
                                width: pixelRect.width,
                                height: pixelRect.height)
            output = pixellated.cropped(to: ciRect).composited(over: output)
        }

        guard let outCG = context.createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: outCG)
    }

    static func save(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }
}

extension UIImage {
    /// Bakes EXIF orientation into pixels; result has .up orientation and
    /// scale 1, so `size` equals the pixel dimensions.
    func normalized() -> UIImage {
        let pixelSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }
}
