import SwiftUI
import Vision

/// Artwork whose main subject (a person, an animal, an object) pops out above the
/// top edge of its card, like the depth effect on iPhone lock screens. The subject
/// is cut out with Vision's foreground mask (macOS 14+); if nothing is found, it's
/// a normal card.
struct DepthArtworkView: View {
    let image: NSImage?
    let size: CGFloat

    @State private var subject: NSImage?

    /// How far down the card's top edge starts, leaving room for the subject to pop out.
    private var topInset: CGFloat { subject == nil ? 0 : size * 0.16 }

    var body: some View {
        ZStack(alignment: .top) {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .mask(alignment: .top) {
                        RoundedRectangle(cornerRadius: size * 0.05, style: .continuous)
                            .padding(.top, topInset)
                    }
                    .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                if let subject {
                    Image(nsImage: subject)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
                        .transition(.opacity)
                }
            } else {
                ArtworkView(image: nil, size: size, cornerRadius: size * 0.05)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.4), value: subject)
        .task(id: image) {
            subject = nil
            guard let image else { return }
            subject = await SubjectLift.subject(of: image)
        }
    }
}

enum SubjectLift {
    /// The image with everything but its foreground subject made transparent,
    /// or nil if Vision finds no subject.
    static func subject(of image: NSImage) async -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = ImageBox(cgImage)
        let output: ImageBox = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: ImageBox(lift(input.image)))
            }
        }
        guard let lifted = output.image else { return nil }
        return NSImage(cgImage: lifted, size: NSSize(width: lifted.width, height: lifted.height))
    }

    private static func lift(_ cgImage: CGImage?) -> CGImage? {
        guard let cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
            let buffer = try observation.generateMaskedImage(
                ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false
            )
            let ciImage = CIImage(cvPixelBuffer: buffer)
            return CIContext().createCGImage(ciImage, from: ciImage.extent)
        } catch {
            return nil
        }
    }

    private final class ImageBox: @unchecked Sendable {
        let image: CGImage?
        init(_ image: CGImage?) { self.image = image }
    }
}
