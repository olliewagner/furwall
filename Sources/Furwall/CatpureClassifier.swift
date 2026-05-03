import Foundation
import Vision
import CoreImage

/// Post-hoc classifier for catpure JPEGs. Runs Vision at full resolution with a
/// generous time budget — distinct from the live `FaceDetector` loop, which
/// operates on tiny frames at 1 Hz under latency pressure. The point is to
/// turn raw "block" stats into something verifiable: "N cats blocked today"
/// rather than "N times we dropped keys for any reason."
///
/// Two questions per image:
///   - Does it actually contain a cat? (`VNRecognizeAnimalsRequest`)
///   - Did we miss a human in the live loop? (`VNDetectFaceRectanglesRequest`
///     OR `VNDetectHumanRectanglesRequest` — face + body, since each catches
///     cases the other misses: face works when the body's clipped, body works
///     when glasses or a downward head-tilt break face detection).
///
/// Calling code uses `containsCat` to decide whether to keep the JPEG —
/// catpures folder is cat-only, anything else gets deleted. `containsHuman`
/// distinguishes confirmed false-positives ("Vision missed me sitting right
/// there") from completely unverified frames; both end in deletion under the
/// current policy but the field is logged for self-evaluation.
enum CatpureClassifier {
    struct Result: Equatable {
        var containsCat: Bool
        var containsHuman: Bool
        var catConfidence: Double
    }

    /// Cat-confidence threshold. Below this, treat the cat as absent. Vision's
    /// animal recognizer is reliable above ~0.5; raising to 0.7 trades a few
    /// hits for fewer false-positive cat sightings on patterned shadows.
    private static let catConfidenceThreshold: Float = 0.7

    /// Classify a single catpure JPEG. Runs off the main actor; the underlying
    /// Vision requests are CPU-bound and fine on a background queue.
    /// Returns nil if the file can't be loaded — caller treats nil as
    /// "unverified," neither cat nor human.
    static func classify(jpegURL: URL) async -> Result? {
        await Task.detached(priority: .utility) {
            guard let image = CIImage(contentsOf: jpegURL) else { return nil }
            let handler = VNImageRequestHandler(ciImage: image, options: [:])

            let animalReq = VNRecognizeAnimalsRequest()
            let humanReq = VNDetectHumanRectanglesRequest()
            humanReq.upperBodyOnly = false  // upper-body OR full body counts as "person present"
            let faceReq = VNDetectFaceRectanglesRequest()

            do {
                try handler.perform([animalReq, humanReq, faceReq])
            } catch {
                return nil
            }

            var catConfidence: Float = 0
            for obs in animalReq.results ?? [] {
                for label in obs.labels where label.identifier.lowercased() == "cat" {
                    catConfidence = max(catConfidence, label.confidence)
                }
            }
            let containsCat = catConfidence >= catConfidenceThreshold
            let bodyDetected = !(humanReq.results ?? []).isEmpty
            let faceDetected = (faceReq.results ?? []).contains { $0.confidence > 0.4 }
            let containsHuman = bodyDetected || faceDetected

            return Result(
                containsCat: containsCat,
                containsHuman: containsHuman,
                catConfidence: Double(catConfidence)
            )
        }.value
    }
}
