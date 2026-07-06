import UIKit
import Vision

enum TextDetector {
    /// Recognizes text in the image and returns padded bounding boxes in
    /// image pixel coordinates (top-left origin), largest first.
    static func detectTextRects(in image: UIImage) async -> [CGRect] {
        guard let cgImage = image.cgImage else { return [] }
        let size = image.size

        let observations: [VNRecognizedTextObservation] = await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                continuation.resume(returning: request.results as? [VNRecognizedTextObservation] ?? [])
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: cgImage).perform([request])
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }

        let padded = observations.map { observation in
            // Vision boxes are normalized with bottom-left origin
            let b = observation.boundingBox
            let rect = CGRect(x: b.minX * size.width,
                              y: (1 - b.maxY) * size.height,
                              width: b.width * size.width,
                              height: b.height * size.height)
            // pad so the mosaic fully covers glyph edges
            let pad = rect.height * 0.2
            return rect.insetBy(dx: -pad, dy: -pad)
        }
        .filter { !$0.isEmpty }

        let gap = max(size.width, size.height) * 0.012
        return merge(padded, gap: gap)
            .map { $0.intersection(CGRect(origin: .zero, size: size)) }
            .filter { !$0.isEmpty }
            .sorted { $0.width * $0.height > $1.width * $1.height }
    }

    /// Repeatedly unions rects that overlap or sit within `gap` of each
    /// other, until no more merges happen (adjacent text lines -> one block).
    private static func merge(_ rects: [CGRect], gap: CGFloat) -> [CGRect] {
        var result = rects
        var merged = true
        while merged {
            merged = false
            outer: for i in result.indices {
                for j in result.indices where j > i {
                    if result[i].insetBy(dx: -gap, dy: -gap).intersects(result[j]) {
                        result[i] = result[i].union(result[j])
                        result.remove(at: j)
                        merged = true
                        break outer
                    }
                }
            }
        }
        return result
    }
}
