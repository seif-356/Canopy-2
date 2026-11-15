import AppKit
import QuickLookThumbnailing
import SwiftUI

/// Plays the AirDrop arrival: a rainbow portal opens at the right edge of the
/// screen, the file comes through it and flies up into the notch (onto the Shelf).
/// Runs in a transparent, click-through window over everything.
@MainActor
final class AirDropAnimator {
    private var window: NSWindow?
    private var queue: [URL] = []
    private var isPlaying = false

    /// Slows the animation down (for CI screenshots).
    var speed: Double = 1

    func play(_ file: URL, notchHeight: CGFloat, completion: @escaping (URL) -> Void) {
        queue.append(file)
        guard !isPlaying else { return }
        playNext(notchHeight: notchHeight, completion: completion)
    }

    private func playNext(notchHeight: CGFloat, completion: @escaping (URL) -> Void) {
        guard !queue.isEmpty, let screen = NSScreen.screens.first else {
            isPlaying = false
            return
        }
        isPlaying = true
        let file = queue.removeFirst()
        Task {
            let thumbnail = await Self.thumbnail(for: file)
            let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            window.isReleasedWhenClosed = false
            let view = AirDropArrivalView(
                thumbnail: thumbnail,
                screenSize: screen.frame.size,
                target: CGPoint(x: screen.frame.width / 2, y: notchHeight / 2),
                speed: speed
            ) { [weak self] in
                self?.window?.orderOut(nil)
                self?.window = nil
                completion(file)
                self?.playNext(notchHeight: notchHeight, completion: completion)
            }
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []
            window.contentView = host
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            self.window = window
        }
    }

    private static func thumbnail(for file: URL) async -> NSImage {
        let request = QLThumbnailGenerator.Request(
            fileAt: file, size: CGSize(width: 240, height: 240), scale: 2, representationTypes: .thumbnail
        )
        if let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            return representation.nsImage
        }
        return NSWorkspace.shared.icon(forFile: file.path(percentEncoded: false))
    }
}

struct AirDropArrivalView: View {
    let thumbnail: NSImage
    let screenSize: CGSize
    /// Where the file ends up (the notch), top-left origin.
    let target: CGPoint
    let speed: Double
    let onFinish: () -> Void

    @State private var portalScale: CGFloat = 0
    @State private var portalSpin: Double = 0
    @State private var itemPosition: CGPoint = .zero
    @State private var itemScale: CGFloat = 0.1
    @State private var itemOpacity: Double = 0
    @State private var itemSpin: Double = -12
    @State private var trail = false

    private var portalCenter: CGPoint { CGPoint(x: screenSize.width, y: screenSize.height * 0.48) }

    var body: some View {
        ZStack {
            // Rainbow portal, half off the right edge.
            ZStack {
                ForEach(0..<5, id: \.self) { ring in
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red],
                                center: .center
                            ),
                            lineWidth: 14 - CGFloat(ring) * 2
                        )
                        .padding(CGFloat(ring) * 26)
                        .opacity(1 - Double(ring) * 0.15)
                }
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.9), .purple.opacity(0.35), .clear],
                                         center: .center, startRadius: 0, endRadius: 120))
                    .padding(110)
            }
            .frame(width: 320, height: 320)
            .rotationEffect(.degrees(portalSpin))
            .scaleEffect(portalScale)
            .blur(radius: 0.5)
            .position(portalCenter)

            // Sparkle trail behind the file.
            ForEach(0..<6, id: \.self) { index in
                Image(systemName: "sparkle")
                    .font(.system(size: CGFloat(18 - index * 2), weight: .bold))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .pink, .purple], startPoint: .top, endPoint: .bottom))
                    .position(trailPoint(index))
                    .opacity(trail ? 0.9 - Double(index) * 0.13 : 0)
            }

            // The file itself.
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 2))
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
                .rotationEffect(.degrees(itemSpin))
                .scaleEffect(itemScale)
                .opacity(itemOpacity)
                .position(itemPosition)
        }
        .frame(width: screenSize.width, height: screenSize.height)
        .ignoresSafeArea()
        .task { await run() }
    }

    /// Points along the way from the portal to the notch, behind the file.
    private func trailPoint(_ index: Int) -> CGPoint {
        let progress = 0.55 - Double(index) * 0.07
        let start = CGPoint(x: portalCenter.x - 60, y: portalCenter.y)
        return CGPoint(
            x: start.x + (target.x - start.x) * progress,
            y: start.y + (target.y - start.y) * progress + sin(progress * .pi) * 80
        )
    }

    private func run() async {
        func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds * speed)) }
        itemPosition = CGPoint(x: portalCenter.x - 40, y: portalCenter.y)

        withAnimation(.spring(response: 0.5 * speed, dampingFraction: 0.65)) { portalScale = 1 }
        withAnimation(.linear(duration: 3 * speed).repeatForever(autoreverses: false)) { portalSpin = 360 }
        await wait(0.45)

        // Out of the portal.
        withAnimation(.spring(response: 0.45 * speed, dampingFraction: 0.6)) {
            itemOpacity = 1
            itemScale = 1
            itemPosition = CGPoint(x: portalCenter.x - 170, y: portalCenter.y + 10)
            itemSpin = 6
        }
        await wait(0.6)

        // Up into the notch.
        withAnimation(.timingCurve(0.55, 0, 0.25, 1, duration: 1.1 * speed)) {
            itemPosition = target
            itemScale = 0.18
            itemSpin = 0
            trail = true
        }
        withAnimation(.easeIn(duration: 0.5 * speed).delay(0.3 * speed)) { portalScale = 0 }
        await wait(0.95)
        withAnimation(.easeOut(duration: 0.25 * speed)) {
            itemOpacity = 0
            trail = false
        }
        await wait(0.3)
        onFinish()
    }
}
