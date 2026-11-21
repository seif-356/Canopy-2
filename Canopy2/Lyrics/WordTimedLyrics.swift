import Foundation

/// Word-timed lyrics from the AMLL TTML DB (github.com/amll-dev/amll-ttml-db,
/// public domain, CC0): a community database of a few thousand songs where every
/// word has its own start and end time. Looked up by title and artist through
/// the database's index, which is cached for a few days.
enum AMLLLyrics {
    static let base = URL(string: "https://raw.githubusercontent.com/amll-dev/amll-ttml-db/main/")!
    static let userAgent = "Canopy2 (https://github.com/seif-356/Canopy-2)"

    static func fetch(title: String, artist: String, duration: Double) async -> [LyricLine]? {
        guard !title.isEmpty, !artist.isEmpty,
              let file = await AMLLIndex.shared.file(title: title, artist: artist) else { return nil }
        let url = base.appendingPathComponent("raw-lyrics").appendingPathComponent(file)
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        guard let response = try? await URLSession.shared.data(for: request),
              (response.1 as? HTTPURLResponse)?.statusCode == 200,
              let lines = TTMLParser.lines(from: response.0) else { return nil }
        // Lyrics that run past the end of the song belong to a longer version of it.
        if duration > 0, let last = lines.last, (last.words?.last?.end ?? last.time) > duration + 3 {
            NSLog("Canopy2 lyrics: word-timed lyrics for %@ are longer than the song, skipped", title)
            return nil
        }
        return lines
    }
}

/// Chooses between line-timed lyrics (LRCLIB) and word-timed ones (AMLL).
enum LyricsSources {
    static func pick(lineTimed: LRCLib.Result, wordTimed: [LyricLine]?, title: String) -> LRCLib.Result {
        guard let wordTimed, !wordTimed.isEmpty else { return lineTimed }
        guard case .synced(let lines) = lineTimed else {
            NSLog("Canopy2 lyrics: word timing for %@ (no line timing to compare)", title)
            return .synced(wordTimed)
        }
        // Same recording? Lines that start with the same words should start at about
        // the same time in both. (Comparing only the first lines fails when one source
        // counts an ad-lib as a line and the other doesn't.)
        var timesByKey: [String: [Double]] = [:]
        for line in lines {
            let key = lineKey(line.text)
            if !key.isEmpty { timesByKey[key, default: []].append(line.time) }
        }
        var offsets: [Double] = []
        for line in wordTimed {
            guard let times = timesByKey[lineKey(line.text)],
                  let nearest = times.min(by: { abs($0 - line.time) < abs($1 - line.time) }) else { continue }
            offsets.append(nearest - line.time)
        }
        guard offsets.count >= 3 else {
            NSLog("Canopy2 lyrics: word timing for %@ can't be checked (%d matching lines), using line timing",
                  title, offsets.count)
            return lineTimed
        }
        let median = offsets.sorted()[offsets.count / 2]
        guard abs(median) <= 1 else {
            // Probably a different recording (other intro, radio edit…): its timings would be off.
            NSLog("Canopy2 lyrics: word timing for %@ is %.1fs off the line timing, using line timing", title, median)
            return lineTimed
        }
        NSLog("Canopy2 lyrics: word timing for %@ (%d lines agree within %.2fs)", title, offsets.count, abs(median))
        return .synced(wordTimed)
    }

    /// The first four words, lowercased, letters and digits only.
    private static func lineKey(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(4)
            .joined(separator: " ")
    }
}

/// The database's index (title, artists → lyrics file), downloaded and cached.
actor AMLLIndex {
    static let shared = AMLLIndex()

    struct Entry: Sendable {
        let artists: [String]
        let file: String
    }

    private var entries: [String: [Entry]]?
    private var lastAttempt: Date?

    func file(title: String, artist: String) async -> String? {
        guard let index = await load() else { return nil }
        let artistKey = Self.normalize(artist)
        guard !artistKey.isEmpty, let candidates = index[Self.normalize(title, isTitle: true)] else { return nil }
        let matches = candidates.filter { entry in
            entry.artists.contains { name in
                let key = Self.normalize(name)
                return !key.isEmpty && (artistKey.contains(key) || key.contains(artistKey))
            }
        }
        // The index lists submissions oldest first; the newest is the best reviewed.
        return matches.last?.file
    }

    private func load() async -> [String: [Entry]]? {
        if let entries { return entries }
        // After a failed download, try again only every ten minutes.
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < 600 { return nil }
        lastAttempt = Date()
        guard let data = await Self.indexData() else { return nil }
        let parsed = Self.parse(data)
        if !parsed.isEmpty { entries = parsed }
        return entries
    }

    private static func indexData() async -> Data? {
        let fileManager = FileManager.default
        let folder = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.seif356.Canopy2", isDirectory: true)
        let cached = folder?.appendingPathComponent("amll-raw-lyrics-index.jsonl")
        if let cached,
           let modified = (try? fileManager.attributesOfItem(atPath: cached.path))?[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) < 3 * 86_400,
           let data = try? Data(contentsOf: cached) {
            return data
        }
        let url = AMLLLyrics.base.appendingPathComponent("metadata").appendingPathComponent("raw-lyrics-index.jsonl")
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(AMLLLyrics.userAgent, forHTTPHeaderField: "User-Agent")
        if let response = try? await URLSession.shared.data(for: request),
           (response.1 as? HTTPURLResponse)?.statusCode == 200 {
            if let folder, let cached {
                try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                try? response.0.write(to: cached)
            }
            return response.0
        }
        // Offline: an old copy beats none.
        return cached.flatMap { try? Data(contentsOf: $0) }
    }

    private static func parse(_ data: Data) -> [String: [Entry]] {
        guard let text = String(data: data, encoding: .utf8) else { return [:] }
        var index: [String: [Entry]] = [:]
        for row in text.split(separator: "\n") {
            guard let object = (try? JSONSerialization.jsonObject(with: Data(row.utf8))) as? [String: Any],
                  let file = object["rawLyricFile"] as? String, isSafeFileName(file),
                  let metadata = object["metadata"] as? [[Any]] else { continue }
            var titles: [String] = []
            var artists: [String] = []
            for pair in metadata where pair.count == 2 {
                guard let key = pair[0] as? String, let values = pair[1] as? [String] else { continue }
                if key == "musicName" { titles = values }
                if key == "artists" { artists = values }
            }
            for title in titles {
                let key = normalize(title, isTitle: true)
                if !key.isEmpty { index[key, default: []].append(Entry(artists: artists, file: file)) }
            }
        }
        return index
    }

    /// Only plain "name.ttml" files, so an index entry can't point anywhere else.
    private static func isSafeFileName(_ name: String) -> Bool {
        name.hasSuffix(".ttml") && !name.isEmpty
            && name.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0) }
            && !name.hasPrefix(".")
    }

    /// Lowercased letters and digits only. Titles also lose "(feat. …)", "[Live]"
    /// and " - Remastered 2011" style suffixes.
    static func normalize(_ text: String, isTitle: Bool = false) -> String {
        var value = text.lowercased()
        if isTitle {
            value = value.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
            if let dash = value.range(of: " - ") { value = String(value[..<dash.lowerBound]) }
        }
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        return String(scalars)
    }
}

/// Reads Apple-style TTML lyrics: <p begin end> lines holding <span begin end>
/// words. Syllables of one word are spans with no space between them.
/// Translations, romanizations and background vocals (spans with a ttm:role)
/// are left out.
final class TTMLParser: NSObject, XMLParserDelegate {
    private struct Span {
        var skipped: Bool
        var begin: Double?
        var end: Double?
        var text = ""
    }

    private struct Line {
        var time: Double
        var words: [TimedWord]
        var text: String
    }

    private var lines: [Line] = []
    private var inParagraph = false
    private var lineBegin = 0.0
    private var words: [TimedWord] = []
    private var looseText = ""
    private var spans: [Span] = []
    private var pending: (text: String, start: Double, end: Double?)?
    private var atBoundary = true

    static func lines(from data: Data) -> [LyricLine]? {
        let delegate = TTMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        let result = delegate.lines
            .sorted { $0.time < $1.time }
            .enumerated()
            .map { index, line in
                LyricLine(id: index, time: line.time, text: line.text, words: line.words.isEmpty ? nil : line.words)
            }
        return result.contains { $0.words != nil } ? result : nil
    }

    func parser(
        _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
        qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "p":
            inParagraph = true
            lineBegin = attributeDict["begin"].flatMap(Self.seconds) ?? 0
            words = []
            looseText = ""
            spans = []
            pending = nil
            atBoundary = true
        case "span" where inParagraph:
            let role = attributeDict["ttm:role"] ?? attributeDict["role"]
            spans.append(Span(
                skipped: (spans.last?.skipped ?? false) || role != nil,
                begin: attributeDict["begin"].flatMap(Self.seconds),
                end: attributeDict["end"].flatMap(Self.seconds)
            ))
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inParagraph else { return }
        if spans.isEmpty {
            looseText += string
            if string.contains(where: \.isWhitespace) { atBoundary = true }
        } else {
            spans[spans.count - 1].text += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch elementName {
        case "span" where inParagraph:
            guard let span = spans.popLast(), !span.skipped else { return }
            let trimmed = span.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if span.text.first?.isWhitespace == true { atBoundary = true }
            if !trimmed.isEmpty, let begin = span.begin {
                if atBoundary || pending == nil {
                    flush()
                    pending = (trimmed, begin, span.end)
                } else if var current = pending {
                    // Another syllable of the same word.
                    current.text += trimmed
                    current.end = span.end ?? current.end
                    pending = current
                }
                atBoundary = false
            }
            if span.text.last?.isWhitespace == true { atBoundary = true }
        case "p" where inParagraph:
            flush()
            let text = words.isEmpty
                ? looseText.trimmingCharacters(in: .whitespacesAndNewlines)
                : words.map(\.text).joined(separator: " ")
            if !text.isEmpty { lines.append(Line(time: lineBegin, words: words, text: text)) }
            inParagraph = false
            spans = []
        default:
            break
        }
    }

    private func flush() {
        if let pending { words.append(TimedWord(text: pending.text, start: pending.start, end: pending.end)) }
        pending = nil
    }

    /// "1:02.5", "00:01:02.500", "62.5" or "62.5s" → seconds.
    static func seconds(_ value: String) -> Double? {
        var text = value.trimmingCharacters(in: .whitespaces)
        if text.hasSuffix("s") { text.removeLast() }
        let parts = text.split(separator: ":").map { Double($0) }
        guard !parts.isEmpty, parts.count <= 3 else { return nil }
        var total = 0.0
        for part in parts {
            guard let part else { return nil }
            total = total * 60 + part
        }
        return total
    }
}
