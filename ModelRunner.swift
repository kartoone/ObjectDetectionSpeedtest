import Foundation
import Vision
import CoreML

final class ModelRunner {
    private var vnModel: VNCoreMLModel?

    /// Initialize with a single model name (default: "yolo11n").
    /// The loader will try, in order:
    /// 1) <name>.mlmodelc in the main bundle
    /// 2) <name>.mlpackage in the main bundle (compile at runtime)
    init(modelName: String = "yolo11n") {
        // 1) Try compiled model in bundle
        if let compiledURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
            do {
                let model = try MLModel(contentsOf: compiledURL)
                self.vnModel = try VNCoreMLModel(for: model)
                return
            } catch {
                // Fall through to try .mlpackage
            }
        }

        // 2) Try .mlpackage in bundle and compile at runtime
        if let packageURL = Bundle.main.url(forResource: modelName, withExtension: "mlpackage") {
            do {
                let compiledURL = try MLModel.compileModel(at: packageURL)
                let model = try MLModel(contentsOf: compiledURL)
                self.vnModel = try VNCoreMLModel(for: model)
                return
            } catch {
                // Failed; leave vnModel nil
            }
        }
    }

    var isLoaded: Bool { vnModel != nil }

    /// Runs prediction and returns (elapsed seconds, recognized object observations).
    func predict(on cgImage: CGImage) async throws -> (time: Double, observations: [VNRecognizedObjectObservation]) {
        guard let vnModel else { throw RunnerError.modelNotLoaded }

        let request = VNCoreMLRequest(model: vnModel)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let start = ContinuousClock().now
        try handler.perform([request])
        let end = ContinuousClock().now

        let duration = start.duration(to: end)
        let comps = duration.components
        let seconds = Double(comps.seconds) + Double(comps.attoseconds) / 1e18

        let observations = (request.results as? [VNRecognizedObjectObservation]) ?? []
        return (seconds, observations)
    }

    /// Runs prediction using Vision and returns the elapsed time in seconds as Double.
    func timePrediction(on cgImage: CGImage) async throws -> Double {
        let (time, _) = try await predict(on: cgImage)
        return time
    }

    enum RunnerError: Error {
        case modelNotLoaded
    }
}
