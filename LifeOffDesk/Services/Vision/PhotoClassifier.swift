import UIKit
import Vision

/// Apple's built-in on-device image classifier (Vision). Names objects in a photo ("tire",
/// "mushroom"); offline, nothing leaves the phone. It does not judge damage, injuries or safety.
enum PhotoClassifier {
    static func labels(for image: UIImage, limit: Int = 5, minimumConfidence: Float = 0.2) async -> [String] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return await Task.detached(priority: .userInitiated) {
            let request = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation)
            do { try handler.perform([request]) } catch { return [] }
            return (request.results ?? [])
                .filter { $0.confidence >= minimumConfidence }
                .sorted { $0.confidence > $1.confidence }
                .prefix(limit)
                .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        }.value
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
