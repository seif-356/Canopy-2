import SwiftUI

/// "Word by word" lyrics: the word being sung, huge, with the one before above it
/// and the one after below it. Some words get a matching symbol ("friends" 👥).
/// Word timings are estimated from the line timings (see `WordTiming`).
struct WordByWordLyrics: View {
    @ObservedObject var player: NowPlayingService
    @ObservedObject var lyrics: LyricsService
    /// Point size of the current word.
    var size: CGFloat = 118

    var body: some View {
        if let track = player.track, lyrics.status == .synced, !lyrics.lines.isEmpty {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !track.isPlaying)) { context in
                let time = track.elapsed(at: context.date)
                WordStack(
                    moment: WordMoment(lines: lyrics.lines, index: lyrics.index(at: time), time: time),
                    size: size,
                    tint: player.palette.primaryColor
                )
            }
        }
    }
}

/// The previous, current and next word at one moment of the song.
struct WordMoment: Equatable {
    var previous: String?
    var current: String
    var next: String?
    /// Changes whenever the current word changes.
    var key: Int

    init(lines: [LyricLine], index: Int?, time: Double) {
        guard let index else {
            // Before the first line.
            previous = nil
            current = "♪"
            next = Self.firstWord(in: lines, after: -1)
            key = -1
            return
        }
        let words = WordTiming.words(in: lines, at: index)
        guard !words.isEmpty else {
            previous = Self.lastWord(in: lines, before: index)
            current = "♪"
            next = Self.firstWord(in: lines, after: index)
            key = index * 1000 + 999
            return
        }
        let word = words.lastIndex { $0.start <= time } ?? 0
        let nextLineTime = index + 1 < lines.count ? lines[index + 1].time : .infinity
        // A long instrumental gap after the line: rest on a note.
        if word == words.count - 1, time - words[word].start > 3, nextLineTime - time > 1 {
            previous = words[word].text
            current = "♪"
            next = Self.firstWord(in: lines, after: index)
            key = index * 1000 + 998
            return
        }
        previous = word > 0 ? words[word - 1].text : Self.lastWord(in: lines, before: index)
        current = words[word].text
        next = word + 1 < words.count ? words[word + 1].text : Self.firstWord(in: lines, after: index)
        key = index * 1000 + word
    }

    private static func firstWord(in lines: [LyricLine], after index: Int) -> String? {
        for candidate in (index + 1)..<min(index + 4, lines.count) where candidate >= 0 {
            if let word = lines[candidate].text.split(whereSeparator: \.isWhitespace).first { return String(word) }
        }
        return nil
    }

    private static func lastWord(in lines: [LyricLine], before index: Int) -> String? {
        var candidate = index - 1
        while candidate >= 0, candidate >= index - 3 {
            if let word = lines[candidate].text.split(whereSeparator: \.isWhitespace).last { return String(word) }
            candidate -= 1
        }
        return nil
    }
}

struct WordStack: View {
    let moment: WordMoment
    let size: CGFloat
    let tint: Color

    var body: some View {
        VStack(spacing: size * 0.06) {
            ZStack {
                Text(moment.previous ?? " ")
                    .font(.system(size: size * 0.29, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .id("previous-\(moment.key)")
                    .transition(.opacity)
            }
            ZStack {
                HStack(spacing: size * 0.12) {
                    Text(moment.current)
                        .font(.system(size: size, weight: .black))
                        .minimumScaleFactor(0.3)
                    if let symbol = WordSymbols.symbol(for: moment.current) {
                        Image(systemName: symbol)
                            .font(.system(size: size * 0.5, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.92))
                    }
                }
                .lineLimit(1)
                .shadow(color: tint.opacity(0.75), radius: size * 0.2)
                .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
                .id(moment.key)
                .transition(.wordPush)
            }
            ZStack {
                Text(moment.next ?? " ")
                    .font(.system(size: size * 0.26, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .id("next-\(moment.key)")
                    .transition(.opacity)
            }
        }
        .lineLimit(1)
        .foregroundStyle(.white)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: moment.key)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WordPushModifier: ViewModifier {
    let scale: CGFloat
    let blur: CGFloat
    let opacity: Double
    let offset: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .blur(radius: blur)
            .opacity(opacity)
            .offset(y: offset)
    }
}

extension AnyTransition {
    /// The new word zooms in out of a blur; the old one shrinks away upward.
    static var wordPush: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: WordPushModifier(scale: 1.45, blur: 16, opacity: 0, offset: 30),
                identity: WordPushModifier(scale: 1, blur: 0, opacity: 1, offset: 0)
            ),
            removal: .modifier(
                active: WordPushModifier(scale: 0.55, blur: 10, opacity: 0, offset: -70),
                identity: WordPushModifier(scale: 1, blur: 0, opacity: 1, offset: 0)
            )
        )
    }
}

/// A few common lyric words and an SF Symbol to go with them.
enum WordSymbols {
    private static let table: [String: String] = {
        let groups: [(String, [String])] = [
            ("heart.fill", ["love", "heart", "hearts", "lover"]),
            ("person.2.fill", ["friends", "friend", "homies", "together"]),
            ("dollarsign.circle.fill", ["money", "cash", "rich", "dollar", "dollars", "paid"]),
            ("moon.fill", ["night", "moon", "midnight", "tonight"]),
            ("sun.max.fill", ["sun", "sunshine", "summer", "daylight"]),
            ("star.fill", ["star", "stars"]),
            ("flame.fill", ["fire", "burn", "burning", "flame", "flames", "heat"]),
            ("cloud.rain.fill", ["rain", "raining", "storm"]),
            ("cloud.fill", ["sky", "cloud", "clouds", "heaven"]),
            ("phone.fill", ["phone", "call", "calling", "ring"]),
            ("car.fill", ["car", "drive", "driving", "ride", "riding"]),
            ("house.fill", ["home", "house"]),
            ("clock.fill", ["time", "clock", "forever"]),
            ("music.note", ["music", "song", "songs", "sing", "dance", "dancing"]),
            ("globe", ["world", "earth", "planet"]),
            ("crown.fill", ["king", "queen", "crown", "royal"]),
            ("eye.fill", ["eyes", "eye", "see", "watch", "watching"]),
            ("lightbulb.fill", ["light", "lights"]),
            ("airplane", ["plane", "fly", "flying", "flight"]),
            ("water.waves", ["ocean", "sea", "wave", "waves", "water"]),
            ("moon.zzz.fill", ["dream", "dreams", "dreaming", "sleep"]),
            ("bolt.fill", ["lightning", "thunder", "electric"]),
            ("snowflake", ["snow", "cold", "ice", "freeze"]),
            ("building.2.fill", ["city", "town", "streets"]),
            ("drop.fill", ["tears", "cry", "crying"]),
            ("face.smiling", ["smile", "smiling", "happy"]),
            ("gamecontroller.fill", ["game", "games", "play"]),
        ]
        var table: [String: String] = [:]
        for (symbol, words) in groups {
            for word in words { table[word] = symbol }
        }
        return table
    }()

    static func symbol(for word: String) -> String? {
        let key = word.lowercased().trimmingCharacters(in: CharacterSet.letters.inverted)
        return table[key]
    }
}
