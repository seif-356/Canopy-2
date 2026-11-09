import AppKit
import CoreImage

/// Artwork scaled to fill `size`, heavily blurred and slightly darkened.
/// Used for the lock-screen background and the desktop skin.
enum ArtworkBlur {
    private static let context = CIContext()

    static func render(_ image: NSImage, size: CGSize, sigma: Double = 45) -> CGImage? {
        guard size.width > 0, size.height > 0,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let target = CGRect(origin: .zero, size: size)
        var output = CIImage(cgImage: cgImage)
        let scale = max(size.width / output.extent.width, size.height / output.extent.height)
        output = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        output = output.transformed(by: CGAffineTransform(
            translationX: (size.width - output.extent.width) / 2 - output.extent.minX,
            y: (size.height - output.extent.height) / 2 - output.extent.minY
        ))
        output = output
            .clampedToExtent()
            .applyingGaussianBlur(sigma: sigma)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: -0.1,
                kCIInputSaturationKey: 1.2,
            ])
            .cropped(to: target)
        return context.createCGImage(output, from: target)
    }
}
