import SwiftUI

/// "Constellation" lyrics: the words of the current line appear one by one as
/// points joined by thin lines, like a star chart. The word being sung is large,
/// marked with a crosshair; the previous line fades out behind it.
///
/// Lyrics only have line timings, so word timings are estimated by spreading the
/// line's time over its words, weighted by length.
struct ConstellationLyrics: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var lyrics: LyricsService

    var body: some View {
        if let track = player.track, lyrics.status == .synced, !lyrics.lines.isEmpty {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !track.isPlaying)) { context in
                ConstellationCanvas(
                    lines: lyrics.lines,
                    time: track.elapsed(at: context.date),
                    current: lyrics.index(at: track.elapsed(at: context.date)),
                    tint: player.palette.primaryColor
                )
            }
        }
    }
}

struct TimedWord {
    let text: String
    let start: Double
}

enum WordTiming {
    /// Estimated start time of each word in line `index`.
    static func words(in lines: [LyricLine], at index: Int) -> [TimedWord] {
        let line = lines[index]
        let words = line.text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        let next = index + 1 < lines.count ? lines[index + 1].time : line.time + 4
        // Don't stretch a line over an instrumental gap.
        let available = min(max(next - line.time, 0.5), Double(words.count) * 0.55 + 1)
        let singing = available * 0.85
        let weights = words.map { Double($0.count) + 1.5 }
        let total = weights.reduce(0, +)
        var start = line.time
        var result: [TimedWord] = []
        for (word, weight) in zip(words, weights) {
            result.append(TimedWord(text: word, start: start))
            start += singing * weight / total
        }
        return result
    }
}

private struct SeededRandom {
    private var state: UInt64

    init(seed: Int) {
        state = UInt64(truncatingIfNeeded: seed) &* 0x9E37_79B9_7F4A_7C15 &+ 0x2545_F491_4F6C_DD1D
    }

    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + next() * (range.upperBound - range.lowerBound)
    }
}

/// Where each word of a line sits, and which words are joined. Same line, same shape.
private struct ConstellationShape {
    let points: [CGPoint]
    let edges: [(Int, Int)]

    init(count: Int, seed: Int, in rect: CGRect) {
        var random = SeededRandom(seed: seed)
        // Short lines stay compact and centred instead of spreading edge to edge.
        let span = min(rect.width, CGFloat(max(count - 1, 0)) * 150)
        let step = span / CGFloat(max(count - 1, 1))
        let left = rect.midX - span / 2
        points = (0..<count).map { index in
            let jitter = count == 1 ? 0 : CGFloat(random.next(in: -0.25...0.25)) * step
            let x = min(max(left + step * CGFloat(index) + jitter, rect.minX), rect.maxX)
            let swing = index.isMultiple(of: 2) ? 1.0 : -0.7
            let y = rect.midY + CGFloat(random.next(in: 0.15...0.5) * swing) * rect.height
            return CGPoint(x: x, y: y)
        }
        var edges: [(Int, Int)] = []
        for index in 1..<max(count, 1) {
            edges.append((index - 1, index))
            if index >= 2, random.next() < 0.45 { edges.append((index - 2, index)) }
            if index >= 3, random.next() < 0.2 { edges.append((index - 3, index)) }
        }
        self.edges = edges
    }
}

struct ConstellationCanvas: View {
    let lines: [LyricLine]
    let time: Double
    let current: Int?
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let band = CGRect(x: size.width * 0.1, y: size.height * 0.18, width: size.width * 0.8, height: size.height * 0.6)
            guard let current else {
                drawNote(in: &context, at: CGPoint(x: size.width / 2, y: size.height / 2))
                return
            }
            // The previous line fades out over the first moment of the new one.
            if current > 0 {
                let fade = 1 - min(max((time - lines[current].time) / 0.9, 0), 1)
                if fade > 0 {
                    drawLine(current - 1, in: &context, band: band.offsetBy(dx: 0, dy: -band.height * 0.25 * (1 - fade)),
                             opacity: fade * 0.5, isCurrent: false, canvas: size)
                }
            }
            drawLine(current, in: &context, band: band, opacity: 1, isCurrent: true, canvas: size)
        }
    }

    private func drawNote(in context: inout GraphicsContext, at point: CGPoint) {
        context.draw(Text("♪").font(.system(size: 34, weight: .bold)).foregroundStyle(.white.opacity(0.7)), at: point)
    }

    private func drawLine(_ index: Int, in context: inout GraphicsContext, band: CGRect, opacity: Double, isCurrent: Bool, canvas: CGSize) {
        let words = WordTiming.words(in: lines, at: index)
        guard !words.isEmpty else {
            if isCurrent { drawNote(in: &context, at: CGPoint(x: band.midX, y: band.midY)) }
            return
        }
        let shape = ConstellationShape(count: words.count, seed: lines[index].id &* 7919 &+ words.count, in: band)
        // How far each word has appeared (0…1); finished lines show fully.
        let appear: [Double] = words.map { word in
            isCurrent ? min(max((time - word.start) / 0.3, 0), 1) : 1
        }
        let sung = isCurrent ? (words.lastIndex { $0.start <= time } ?? -1) : -1

        // Links.
        for (from, to) in shape.edges where appear[from] > 0 && appear[to] > 0 {
            let a = shape.points[from]
            let b = shape.points[to]
            let progress = appear[to]
            var path = Path()
            path.move(to: a)
            path.addLine(to: CGPoint(x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress))
            context.stroke(path, with: .color(.white.opacity(0.35 * opacity)), lineWidth: 0.8)
        }

        // Stars and their words.
        for (index, word) in words.enumerated() where appear[index] > 0 {
            let point = shape.points[index]
            let alpha = appear[index] * opacity
            let dot = Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5))
            context.fill(dot, with: .color(.white.opacity(0.9 * alpha)))

            if index == sung {
                drawCrosshair(in: &context, at: point, alpha: alpha)
                let text = context.resolve(
                    Text(word.text).font(.system(size: 40, weight: .heavy)).foregroundStyle(.white.opacity(alpha))
                )
                // Right of the star, or left of it when it would run off the edge.
                let width = text.measure(in: canvas).width
                let fitsRight = point.x + 14 + width <= canvas.width - 8
                context.drawLayer { layer in
                    layer.addFilter(.shadow(color: tint.opacity(0.8), radius: 14))
                    layer.draw(
                        text,
                        at: CGPoint(x: fitsRight ? point.x + 14 : max(point.x - 14, width + 8), y: point.y + 10),
                        anchor: fitsRight ? .topLeading : .topTrailing
                    )
                }
            } else {
                let text = context.resolve(
                    Text(word.text).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.6 * alpha))
                )
                let fitsRight = point.x + 7 + text.measure(in: canvas).width <= canvas.width - 8
                context.draw(
                    text,
                    at: CGPoint(x: fitsRight ? point.x + 7 : point.x - 7, y: point.y - 5),
                    anchor: fitsRight ? .bottomLeading : .bottomTrailing
                )
            }
        }
    }

    private func drawCrosshair(in context: inout GraphicsContext, at point: CGPoint, alpha: Double) {
        let radius: CGFloat = 11
        var path = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        path.move(to: CGPoint(x: point.x - radius - 5, y: point.y))
        path.addLine(to: CGPoint(x: point.x + radius + 5, y: point.y))
        path.move(to: CGPoint(x: point.x, y: point.y - radius - 5))
        path.addLine(to: CGPoint(x: point.x, y: point.y + radius + 5))
        context.stroke(path, with: .color(.white.opacity(alpha)), lineWidth: 1.2)
    }
}
