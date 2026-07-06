import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Photos

enum MosaicProcessor {
    private static let context = CIContext()

    /// Pixellates the given rects (in image pixel coordinates, top-left
    /// origin) and composites them over the original image.
    static func applyMosaics(to image: UIImage, in pixelRects: [CGRect]) -> UIImage? {
        guard !pixelRects.isEmpty else { return image }
        guard let cgImage = image.cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)

        let filter = CIFilter.pixellate()
        filter.inputImage = input
        // Block size proportional to image dimension, never smaller than 8 px
        filter.scale = Float(max(max(input.extent.width, input.extent.height) / 50, 8))
        filter.center = CGPoint(x: input.extent.midX, y: input.extent.midY)

        // CIPixellate has infinite extent — crop back to the image bounds
        guard let pixellated = filter.outputImage?.cropped(to: input.extent) else { return nil }

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
