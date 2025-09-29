//
//  ContentView.swift
//  objspeed
//
//  Created by Brian Toone on 9/28/25.
//

import SwiftUI
import PhotosUI
import Vision
import CoreML

struct ContentView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var originalImage: UIImage?
    @State private var processedImage: UIImage?

    @State private var rotateTime: Double?
    @State private var resizeTime: Double?
    @State private var predictionTime: Double?
    @State private var statusMessage: String = "Pick an image to begin"
    @State private var isShowingLiDARCapture = false

    @State private var preloadProgress: String? = nil

    struct ModelPredictionResult: Identifiable {
        let id = UUID()
        let modelName: String
        let time: Double
        let overlay: UIImage?
        let count: Int
    }
    struct ModelLoadResult: Identifiable {
        let id = UUID()
        let modelName: String
        let kind: String // "Detection" or "Segmentation"
        let time: Double // seconds
    }

    @State private var modelResults: [ModelPredictionResult] = []
    @State private var modelLoadResults: [ModelLoadResult] = []
    @State private var gridImage: UIImage?
    @State private var modelRunnerCache: [String: ModelRunner] = [:]
    @State private var segmentationModelCache: [String: VNCoreMLModel] = [:]
    @State private var isPreloadingModels: Bool = false
    @State private var didKickoffPreload: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                        Label("Browse Photo", systemImage: "photo.on.rectangle")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button(action: { isShowingLiDARCapture = true }) {
                        Label("Capture with LiDAR", systemImage: "cube")
                            .font(.headline)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Group {
                        if isPreloadingModels {
                            HStack(spacing: 12) {
                                ProgressView()
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Loading models…")
                                        .font(.headline)
                                    if let progress = preloadProgress {
                                        Text(progress)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.accentColor.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else if !modelLoadResults.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle")
                                    .foregroundStyle(.green)
                                Text("Models loaded")
                                    .font(.headline)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.accentColor.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    if let originalImage, let processedImage {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Original Image").font(.headline)
                                Image(uiImage: originalImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .border(.secondary)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Processed (rotated 180°)").font(.headline)
                                Image(uiImage: processedImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .border(.secondary)
                            }
                        }
                    } else {
                        if let originalImage {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Original Image").font(.headline)
                                Image(uiImage: originalImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity)
                                    .border(.secondary)
                            }
                        }

                        if let processedImage {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Processed (rotated 180°)").font(.headline)
                                Image(uiImage: processedImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .border(.secondary)
                            }
                        }
                    }

                    if let processedImage {
                        VStack(alignment: .leading, spacing: 8) {
                            let columns = [GridItem(.adaptive(minimum: 240), spacing: 12, alignment: .top)]
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                                ForEach(modelResults) { result in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Prediction – \(result.modelName)")
                                            .font(.headline)
                                        ZStack {
                                            Image(uiImage: gridImage ?? processedImage)
                                                .resizable()
                                                .scaledToFill()
                                                .clipped()
                                            if let overlay = result.overlay {
                                                Image(uiImage: overlay)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .clipped()
                                            }
                                        }
                                        .aspectRatio(1, contentMode: .fit)
                                        .border(.tertiary)

                                        HStack(spacing: 12) {
                                            Text("Detections: \(result.count)")
                                            Spacer()
                                            Text(msString(result.time))
                                        }
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    }
                                    .padding(10)
                                    .background(Color(.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Timing (milliseconds)").font(.headline)
                        HStack {
                            Text("Rotate 180°:")
                            Spacer()
                            Text(msString(rotateTime))
                        }
                        HStack {
                            Text("Resize to 640×640:")
                            Spacer()
                            Text(msString(resizeTime))
                        }
                        HStack {
                            Text("Prediction:")
                            Spacer()
                            Text(msString(predictionTime))
                        }
                        ForEach(modelResults) { result in
                            HStack {
                                Text("Prediction (\(result.modelName)):")
                                Spacer()
                                Text(msString(result.time))
                            }
                        }

                        Divider()
                        Text("Model Load Times (milliseconds)").font(.headline)
                        ForEach(modelLoadResults) { load in
                            HStack {
                                Text("\(load.kind) (\(load.modelName)):")
                                Spacer()
                                Text(msString(load.time))
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle("YOLO Timing")
        }
        .task {
            if !didKickoffPreload {
                didKickoffPreload = true
                await preloadModels()
            }
        }
        .sheet(isPresented: $isShowingLiDARCapture) {
            LiDARCaptureView { image in
                // Dismiss and process
                isShowingLiDARCapture = false
                Task { await processAndPredict(image) }
            }
        }
        .onChange(of: selectedItem) { oldValue, newValue in
            Task { await handleSelectionChange() }
        }
    }

    private func msString(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f ms", value * 1000)
    }

    @MainActor
    private func handleSelectionChange() async {
        guard let selectedItem else { return }
        statusMessage = "Loading image…"
        rotateTime = nil
        resizeTime = nil
        predictionTime = nil
        processedImage = nil

        do {
            if let data = try await selectedItem.loadTransferable(type: Data.self), let uiImage = UIImage(data: data) {
                await processAndPredict(uiImage)
            } else {
                statusMessage = "Failed to load image data."
            }
        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func preloadModels() async {
        await MainActor.run {
            isPreloadingModels = true
            statusMessage = "Preloading models…"
        }
        var loads: [ModelLoadResult] = []

        var detToInsert: [String: ModelRunner] = [:]
        var segToInsert: [String: VNCoreMLModel] = [:]

        let detectionModels = ["yolo11n", "yolo11s", "yolo11m", "yolo11l", "yolo11x"]
        let segmentationModels = ["DETRResnet50SemanticSegmentationF16"]

        let totalToLoad = detectionModels.filter { modelRunnerCache[$0] == nil }.count +
                          segmentationModels.filter { segmentationModelCache[$0] == nil }.count
        var loadedCount = 0

        // Detection model runners
        for name in detectionModels {
            if modelRunnerCache[name] == nil {
                await MainActor.run {
                    preloadProgress = "Detection: \(name) (\(loadedCount + 1)/\(max(totalToLoad, 1)))"
                }
                let start = ContinuousClock().now
                let runner = await Task.detached(priority: .background) { ModelRunner(modelName: name) }.value
                let end = ContinuousClock().now
                let comps = start.duration(to: end).components
                let secs = Double(comps.seconds) + Double(comps.attoseconds) / 1e18
                detToInsert[name] = runner
                loads.append(ModelLoadResult(modelName: name, kind: "Detection", time: secs))

                loadedCount += 1
                await MainActor.run {
                    preloadProgress = "Loaded: \(name) (\(loadedCount)/\(max(totalToLoad, 1)))"
                }

            } else {
                loads.append(ModelLoadResult(modelName: name, kind: "Detection", time: 0))
                loadedCount += 1
                await MainActor.run {
                    preloadProgress = "Cached: \(name) (\(loadedCount)/\(max(totalToLoad, 1)))"
                }
            }
        }

        // Segmentation VNCoreMLModels (.mlpackage preferred, fallback to .mlmodelc)
        for name in segmentationModels {
            if segmentationModelCache[name] == nil {
                await MainActor.run {
                    preloadProgress = "Segmentation: \(name) (\(loadedCount + 1)/\(max(totalToLoad, 1)))"
                }
                let start = ContinuousClock().now
                let loaded: VNCoreMLModel? = await Task.detached(priority: .background) { () -> VNCoreMLModel? in
                    if let pkgURL = Bundle.main.url(forResource: name, withExtension: "mlpackage"),
                       let mlModel = try? MLModel(contentsOf: pkgURL),
                       let vn = try? VNCoreMLModel(for: mlModel) {
                        return vn
                    } else if let compiledURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc"),
                              let mlModel = try? MLModel(contentsOf: compiledURL),
                              let vn = try? VNCoreMLModel(for: mlModel) {
                        return vn
                    }
                    return nil
                }.value
                let end = ContinuousClock().now
                let comps = start.duration(to: end).components
                let secs = Double(comps.seconds) + Double(comps.attoseconds) / 1e18
                if let vn = loaded {
                    segToInsert[name] = vn
                    loads.append(ModelLoadResult(modelName: name, kind: "Segmentation", time: secs))
                } else {
                    loads.append(ModelLoadResult(modelName: name, kind: "Segmentation", time: 0))
                }

                loadedCount += 1
                await MainActor.run {
                    preloadProgress = "Loaded: \(name) (\(loadedCount)/\(max(totalToLoad, 1)))"
                }

            } else {
                loads.append(ModelLoadResult(modelName: name, kind: "Segmentation", time: 0))
                loadedCount += 1
                await MainActor.run {
                    preloadProgress = "Cached: \(name) (\(loadedCount)/\(max(totalToLoad, 1)))"
                }
            }
        }

        await MainActor.run {
            // Commit loaded models to caches on the main actor
            for (k, v) in detToInsert { modelRunnerCache[k] = v }
            for (k, v) in segToInsert { segmentationModelCache[k] = v }
            modelLoadResults = loads
            preloadProgress = nil
            isPreloadingModels = false
            statusMessage = "Models preloaded"
        }
    }

    @MainActor
    private func processAndPredict(_ uiImage: UIImage) async {
        self.originalImage = uiImage
        statusMessage = "Processing…"

        // Rotate 180°
        let rotateStart = ContinuousClock().now
        let rotated = uiImage.rotated(radians: .pi)
        let rotateEnd = ContinuousClock().now
        let rotateDuration = rotateStart.duration(to: rotateEnd)
        let rotateComps = rotateDuration.components
        self.rotateTime = Double(rotateComps.seconds) + Double(rotateComps.attoseconds) / 1e18

        self.processedImage = rotated
        self.gridImage = rotated.resized(to: CGSize(width: 640, height: 640))

        // Commented out resize timing and operation
        // Resize to 640x640
        let resizeStart = ContinuousClock().now
        let resized = rotated.resized(to: CGSize(width: 640, height: 640))
        let resizeEnd = ContinuousClock().now
        let resizeDuration = resizeStart.duration(to: resizeEnd)
        let resizeComps = resizeDuration.components
        self.resizeTime = Double(resizeComps.seconds) + Double(resizeComps.attoseconds) / 1e18
        self.processedImage = resized

        // Run predictions for multiple models and time each, then draw overlays
        guard let cgImage = resized.cgImage else {
            statusMessage = "Failed to create CGImage from processed image."
            return
        }

        statusMessage = "Running predictions…"
        let detectionModels = ["yolo11n", "yolo11s", "yolo11m", "yolo11l", "yolo11x"]
        let segmentationModels = ["DETRResnet50SemanticSegmentationF16"]
        self.modelResults = []

        // Preload detection model runners so we reuse them across predictions
        for name in detectionModels {
            if modelRunnerCache[name] == nil {
                modelRunnerCache[name] = ModelRunner(modelName: name)
            }
        }
        // Preload Vision segmentation models (.mlpackage preferred, fallback to .mlmodelc)
        for name in segmentationModels {
            if segmentationModelCache[name] == nil {
                var loaded: VNCoreMLModel? = nil
                if let pkgURL = Bundle.main.url(forResource: name, withExtension: "mlpackage"),
                   let mlModel = try? MLModel(contentsOf: pkgURL),
                   let vn = try? VNCoreMLModel(for: mlModel) {
                    loaded = vn
                } else if let compiledURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc"),
                          let mlModel = try? MLModel(contentsOf: compiledURL),
                          let vn = try? VNCoreMLModel(for: mlModel) {
                    loaded = vn
                }
                if let vn = loaded { segmentationModelCache[name] = vn }
            }
        }

        // Run detection models
        for name in detectionModels {
            try? await Task.sleep(nanoseconds: 1) // yield to UI briefly
            do {
                guard let runner = modelRunnerCache[name] else { continue }
                let (predTime, observations) = try await runner.predict(on: cgImage)
                let overlay = drawDetections(size: CGSize(width: 640, height: 640), observations: observations)
                let result = ModelPredictionResult(modelName: name, time: predTime, overlay: overlay, count: observations.count)
                self.modelResults.append(result)
            } catch {
                let result = ModelPredictionResult(modelName: name, time: 0, overlay: nil, count: 0)
                self.modelResults.append(result)
            }
        }

        // Run segmentation models
        for name in segmentationModels {
            try? await Task.sleep(nanoseconds: 1)
            do {
                let (segTime, mask) = try await runSegmentation(modelName: name, cgImage: cgImage)
                let overlay = drawSegmentationOverlay(mask: mask, size: CGSize(width: 640, height: 640))
                let result = ModelPredictionResult(modelName: name, time: segTime, overlay: overlay, count: 0)
                self.modelResults.append(result)
            } catch {
                let result = ModelPredictionResult(modelName: name, time: 0, overlay: nil, count: 0)
                self.modelResults.append(result)
            }
        }

        statusMessage = "Done"
    }

    private func drawDetections(size: CGSize, observations: [VNRecognizedObjectObservation]) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.clear.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.setLineWidth(2)

            for obs in observations {
                // VN uses normalized bounding boxes in a coordinate space with origin at bottom-left.
                // Our image is in UIKit coordinates (origin at top-left). Convert accordingly.
                let bbox = obs.boundingBox
                let rect = CGRect(x: bbox.minX * size.width,
                                  y: (1 - bbox.maxY) * size.height,
                                  width: bbox.width * size.width,
                                  height: bbox.height * size.height)

                // Choose a color per top label
                let color: UIColor
                if let top = obs.labels.first {
                    // Hash the identifier into a color
                    var hasher = Hasher()
                    hasher.combine(top.identifier)
                    let hash = hasher.finalize()
                    let r = CGFloat((hash & 0xFF)) / 255.0
                    let g = CGFloat((hash >> 8) & 0xFF) / 255.0
                    let b = CGFloat((hash >> 16) & 0xFF) / 255.0
                    color = UIColor(red: r, green: g, blue: b, alpha: 1)
                } else {
                    color = .systemYellow
                }
                cg.setStrokeColor(color.cgColor)
                cg.stroke(rect)

                // Draw label text background
                let label: String
                if let top = obs.labels.first {
                    label = String(format: "%@ %.2f", top.identifier, top.confidence)
                } else {
                    label = "object"
                }
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
                    .foregroundColor: UIColor.white,
                ]
                let textSize = label.size(withAttributes: attrs)
                let bgRect = CGRect(x: rect.minX, y: max(rect.minY - textSize.height - 4, 0), width: textSize.width + 8, height: textSize.height + 4)
                cg.setFillColor(color.withAlphaComponent(0.8).cgColor)
                cg.fill(bgRect)
                label.draw(in: bgRect.insetBy(dx: 4, dy: 2), withAttributes: attrs)
            }
        }
    }

    // MARK: - Vision-based Semantic Segmentation
    private func runSegmentation(modelName: String, cgImage: CGImage) async throws -> (Double, CVPixelBuffer) {
        // Get or load VNCoreMLModel from cache
        let vnModel: VNCoreMLModel
        if let cached = segmentationModelCache[modelName] {
            vnModel = cached
        } else {
            // Try .mlpackage first, then .mlmodelc
            let url: URL
            if let pkgURL = Bundle.main.url(forResource: modelName, withExtension: "mlpackage") {
                url = pkgURL
            } else if let compiledURL = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
                url = compiledURL
            } else {
                throw NSError(domain: "Segmentation", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model \(modelName) not found as .mlpackage or .mlmodelc in bundle."])
            }
            let mlModel = try MLModel(contentsOf: url)
            vnModel = try VNCoreMLModel(for: mlModel)
            segmentationModelCache[modelName] = vnModel
        }

        // Prepare request
        var outputPixelBuffer: CVPixelBuffer?
        let request = VNCoreMLRequest(model: vnModel) { request, _ in
            if let first = request.results?.first as? VNPixelBufferObservation {
                outputPixelBuffer = first.pixelBuffer
            } else if let firstFV = request.results?.first as? VNCoreMLFeatureValueObservation {
                if let pb = firstFV.featureValue.imageBufferValue {
                    outputPixelBuffer = pb
                } else if let multi = firstFV.featureValue.multiArrayValue {
                    outputPixelBuffer = maskFromMultiArray(multi)
                }
            }
        }
        request.imageCropAndScaleOption = .scaleFill

        // Time the request
        let start = ContinuousClock().now
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let end = ContinuousClock().now
        let dur = start.duration(to: end).components
        let time = Double(dur.seconds) + Double(dur.attoseconds) / 1e18

        guard let mask = outputPixelBuffer else {
            print("No pixel buffer result from segmentation")
            throw NSError(domain: "Segmentation", code: -2, userInfo: [NSLocalizedDescriptionKey: "No pixel buffer result from segmentation."])
        }
        return (time, mask)
    }

    private func drawSegmentationOverlay(mask: CVPixelBuffer, size: CGSize, tint: UIColor = .systemGreen, alpha: CGFloat = 0.35) -> UIImage? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        let maskWidth = CVPixelBufferGetWidth(mask)
        let maskHeight = CVPixelBufferGetHeight(mask)
        guard let baseAddr = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(mask)

        // Create a CGImage from the single-channel mask
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let dataProvider = CGDataProvider(dataInfo: nil, data: baseAddr, size: bytesPerRow * maskHeight, releaseData: { _,_,_ in }) else { return nil }
        guard let maskImage = CGImage(width: maskWidth,
                                      height: maskHeight,
                                      bitsPerComponent: 8,
                                      bitsPerPixel: 8,
                                      bytesPerRow: bytesPerRow,
                                      space: colorSpace,
                                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                      provider: dataProvider,
                                      decode: nil,
                                      shouldInterpolate: false,
                                      intent: .defaultIntent) else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            let cg = ctx.cgContext
            cg.setFillColor(UIColor.clear.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            cg.saveGState()
            cg.interpolationQuality = .none
            // Flip to UIKit coordinates and scale mask to output size
            cg.translateBy(x: 0, y: size.height)
            cg.scaleBy(x: size.width / CGFloat(maskWidth), y: -size.height / CGFloat(maskHeight))

            // Clip to mask then fill with tinted color
            cg.clip(to: CGRect(x: 0, y: 0, width: maskWidth, height: maskHeight), mask: maskImage)
            cg.setFillColor(tint.withAlphaComponent(alpha).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: maskWidth, height: maskHeight))

            cg.restoreGState()
        }
    }

    // Convert a segmentation output MLMultiArray into an 8-bit mask (argmax over classes).
    // Supports shapes: [N, C, H, W], [C, H, W], [H, W, C]. Background is assumed class 0.
    private func maskFromMultiArray(_ arr: MLMultiArray) -> CVPixelBuffer? {
        let shape = arr.shape.map { Int(truncating: $0) }
        let strides = arr.strides.map { Int(truncating: $0) }
        let dims = shape.count
        let (C, H, W, layout): (Int, Int, Int, Int)
        // layout codes: 0 = NCHW (with optional N), 1 = CHW, 2 = HWC
        if dims == 4 {
            // [N, C, H, W]
            C = shape[1]; H = shape[2]; W = shape[3]; layout = 0
        } else if dims == 3 {
            // Heuristic: if first dim looks like channels, treat as CHW; otherwise HWC
            if shape[0] <= 256 && shape[0] != shape[1] && shape[0] != shape[2] {
                C = shape[0]; H = shape[1]; W = shape[2]; layout = 1
            } else {
                H = shape[0]; W = shape[1]; C = shape[2]; layout = 2
            }
        } else if dims == 2 {
            // Already class indices per pixel [H, W]
            let H = shape[0], W = shape[1]
            var pb: CVPixelBuffer?
            let attrs: [CFString: Any] = [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true
            ]
            guard CVPixelBufferCreate(kCFAllocatorDefault, W, H, kCVPixelFormatType_OneComponent8, attrs as CFDictionary, &pb) == kCVReturnSuccess, let pixelBuffer = pb else { return nil }
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
            guard let basePtr = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

            // Read values as doubles (works for int/float types when converted)
            let total = H * W
            for h in 0..<H {
                let rowPtr = basePtr.advanced(by: h * bytesPerRow)
                for w in 0..<W {
                    let idx = h * W + w
                    let v = arr[idx].doubleValue
                    let cls = Int(v.rounded())
                    let maskVal: UInt8 = cls == 0 ? 0 : 255
                    let pixelAddr = rowPtr.advanced(by: w)
                    pixelAddr.storeBytes(of: maskVal, as: UInt8.self)
                }
            }
            return pixelBuffer
        } else {
            return nil
        }

        // Create an 8-bit grayscale pixel buffer HxW
        var pb: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, W, H, kCVPixelFormatType_OneComponent8, attrs as CFDictionary, &pb) == kCVReturnSuccess, let pixelBuffer = pb else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let basePtr = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        // Data access helpers
        let dt = arr.dataType
        let raw = arr.dataPointer
        func value(at offset: Int) -> Double {
            switch dt {
            case .float32:
                return Double(raw.assumingMemoryBound(to: Float32.self)[offset])
            case .double:
                return raw.assumingMemoryBound(to: Double.self)[offset]
            case .float16:
                let u16 = raw.assumingMemoryBound(to: UInt16.self)[offset]
                return Double(Float16(bitPattern: u16))
            case .int32:
                return Double(raw.assumingMemoryBound(to: Int32.self)[offset])
            default:
                return 0
            }
        }

        // Argmax across channels for each pixel
        let s = strides
        for h in 0..<H {
            let rowPtr = basePtr.advanced(by: h * bytesPerRow)
            for w in 0..<W {
                var bestClass = 0
                var bestScore = -Double.greatestFiniteMagnitude
                if layout == 0 {
                    // [N, C, H, W] with strides [sN, sC, sH, sW]
                    let sC = s[1], sH = s[2], sW = s[3]
                    let base = sH * h + sW * w
                    for c in 0..<C {
                        let idx = sC * c + base
                        let v = value(at: idx)
                        if v > bestScore { bestScore = v; bestClass = c }
                    }
                } else if layout == 1 {
                    // [C, H, W] with strides [sC, sH, sW]
                    let sC = s[0], sH = s[1], sW = s[2]
                    let base = sH * h + sW * w
                    for c in 0..<C {
                        let idx = sC * c + base
                        let v = value(at: idx)
                        if v > bestScore { bestScore = v; bestClass = c }
                    }
                } else {
                    // [H, W, C] with strides [sH, sW, sC]
                    let sH = s[0], sW = s[1], sC = s[2]
                    let base = sH * h + sW * w
                    for c in 0..<C {
                        let idx = base + sC * c
                        let v = value(at: idx)
                        if v > bestScore { bestScore = v; bestClass = c }
                    }
                }
                let maskVal: UInt8 = bestClass == 0 ? 0 : 255
                let pixelAddr = rowPtr.advanced(by: w)
                pixelAddr.storeBytes(of: maskVal, as: UInt8.self)
            }
        }
        return pixelBuffer
    }
}

