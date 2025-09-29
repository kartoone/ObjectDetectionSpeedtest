import SwiftUI
import ARKit

struct LiDARCaptureView: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> ARViewController {
        return ARViewController(onCapture: onCapture)
    }

    func updateUIViewController(_ uiViewController: ARViewController, context: Context) {}
}

final class ARViewController: UIViewController, ARSessionDelegate {
    private let session = ARSession()
    private let onCapture: (UIImage) -> Void

    private let previewView = UIImageView()
    private let captureButton = UIButton(type: .system)

    init(onCapture: @escaping (UIImage) -> Void) {
        self.onCapture = onCapture
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Configure preview
        previewView.contentMode = .scaleAspectFit
        previewView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewView)

        // Configure capture button
        captureButton.setTitle("Capture", for: .normal)
        captureButton.titleLabel?.font = .boldSystemFont(ofSize: 18)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.addTarget(self, action: #selector(capturePressed), for: .touchUpInside)
        view.addSubview(captureButton)

        NSLayoutConstraint.activate([
            previewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: view.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -12),

            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])

        session.delegate = self

        // Ensure device supports LiDAR
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        session.run(config)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.pause()
    }

    /// Compute UIImage orientation matching the current UI orientation for the camera feed.
    private func currentImageOrientation() -> UIImage.Orientation {
        // Prefer interface orientation from the active window scene
        let interfaceOrientation: UIInterfaceOrientation? = view.window?.windowScene?.interfaceOrientation ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation

        switch interfaceOrientation {
        case .some(.portrait):
            return .right
        case .some(.portraitUpsideDown):
            return .left
        case .some(.landscapeLeft):
            // Device/home on the left -> keep image upright
            return .up
        case .some(.landscapeRight):
            // Device/home on the right -> rotate 180 to stay upright
            return .down
        default:
            // Fallback using device orientation
            switch UIDevice.current.orientation {
            case .portrait:
                return .right
            case .portraitUpsideDown:
                return .left
            case .landscapeLeft:
                return .up
            case .landscapeRight:
                return .down
            default:
                return .up
            }
        }
    }

    @objc private func capturePressed() {
        guard let currentFrame = session.currentFrame else { return }
        let pixelBuffer = currentFrame.capturedImage
        let image = UIImage(pixelBuffer: pixelBuffer, orientation: currentImageOrientation())
        onCapture(image)
        dismiss(animated: true)
    }

    // Update preview image as frames arrive (lightweight)
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let pixelBuffer = frame.capturedImage
        let image = UIImage(pixelBuffer: pixelBuffer, orientation: currentImageOrientation())
        DispatchQueue.main.async { [weak self] in
            self?.previewView.image = image
        }
    }
}

private extension UIImage {
    convenience init(pixelBuffer: CVPixelBuffer, orientation: UIImage.Orientation) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)!
        self.init(cgImage: cgImage, scale: 1, orientation: orientation)
    }
}
