import UIKit

extension UIImage {
    /// Rotates the image by radians around its center, expanding canvas as needed.
    func rotated(radians: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            ctx.cgContext.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.cgContext.rotate(by: radians)
            ctx.cgContext.translateBy(x: -size.width / 2, y: -size.height / 2)
            self.draw(in: rect)
        }
    }

    /// Resizes the image to an exact size using aspect fill then center-crop to target if needed.
    func resized(to targetSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // Keep pixel math straightforward; resulting CGImage size == targetSize in points
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            let sourceSize = self.size
            let scale = max(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
            let newSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            let origin = CGPoint(x: (targetSize.width - newSize.width) / 2, y: (targetSize.height - newSize.height) / 2)
            self.draw(in: CGRect(origin: origin, size: newSize))
        }
    }
}
