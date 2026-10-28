import Combine
import Foundation

/// One line of time-synced lyrics.
struct LyricLine: Equatable {
    let time: Double
    let text: String
}

/// Finds lyrics for the song playing on LRCLIB (lrclib.net: free, no account), preferring
/// time-synced ones, and works out which line is being sung.
/// Only the song's title, artist and length are sent; nothing is looked up while lyrics are off.
final class LyricsManager: ObservableObject {
    enum Status: Equatable {
        case off, idle, loading, synced, plain, notFound
    }

    @Published private(set) var status: Status = .idle
    /// Synced lines, sorted by time (empty for plain lyrics).
    @Published private(set) var lines: [LyricLine] = []
    /// Unsynced lyrics, when that's all LRCLIB has.
    @Published private(set) var plainText = ""

    var isOn: Bool { UserDefaults.standard.bool(forKey: "lyrics") }
    var hasLyrics: Bool { status == .synced || status == .plain }

    private var cache: [String: (lines: [LyricLine], plain: String)] = [:]
    private var key = ""
    private var task: Task<Void, Never>?
    private var subscription: AnyCancellable?

    init(music: MusicManager) {
        // The player reports title, artist and length a moment apart; wait for them to settle.
        subscription = Publishers.CombineLatest3(music.$title, music.$artist, music.$duration)
            .debounce(for: .seconds(0.6), scheduler: DispatchQueue.main)
            .sink { [weak self] title, artist, duration in
                self?.lookUp(title: title, artist: artist, duration: duration)
            }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self, weak music] _ in
            guard let self, let music else { return }
            if self.isOn == (self.status == .off) {
                self.key = ""
                self.lookUp(title: music.title, artist: music.artist, duration: music.duration)
            }
        }
    }

    /// Index of the line being sung at `position` seconds.
    func currentIndex(at position: Double) -> Int? {
        // A little ahead, so the line shows as the singer starts it rather than just after.
        let t = position + 0.25
        guard let first = lines.first, t >= first.time else { return nil }
        var low = 0, high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].time <= t { low = mid } else { high = mid - 1 }
        }
        return low
    }

    // MARK: Lookup

    private func lookUp(title: String, artist: String, duration: Double) {
        guard isOn else {
            task?.cancel()
            set(.off)
            return
        }
        guard !title.isEmpty else {
            task?.cancel()
            key = ""
            set(.idle)
            return
        }
        let newKey = "\(title)|\(artist)"
        // Same song; only look again if the first try ran before the length was known.
        guard newKey != key || (status == .notFound && duration > 0 && cache[newKey] == nil) else { return }
        key = newKey
        task?.cancel()
        if let hit = cache[newKey] {
            apply(hit)
            return
        }
        set(.loading)
        task = Task {
            let found = await Self.fetch(title: title, artist: artist, duration: duration)
            let cancelled = Task.isCancelled
            await MainActor.run { [weak self] in
                guard let self, !cancelled, self.key == newKey else { return }
                if let found { self.cache[newKey] = found }
                self.apply(found)
                NSLog("%@", "Islet lyrics: \(title) — \(self.status == .synced ? "\(self.lines.count) synced lines" : "\(self.status)")")
            }
        }
    }

    private func apply(_ found: (lines: [LyricLine], plain: String)?) {
        lines = found?.lines ?? []
        plainText = found?.plain ?? ""
        set(!lines.isEmpty ? .synced : !plainText.isEmpty ? .plain : .notFound)
    }

    private func set(_ s: Status) {
        if s == .off || s == .idle || s == .loading {
            if !lines.isEmpty { lines = [] }
            if !plainText.isEmpty { plainText = "" }
        }
        if status != s { status = s }
    }

    private struct Record: Decodable {
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    private static func fetch(title: String, artist: String, duration: Double) async -> (lines: [LyricLine], plain: String)? {
        let song = cleanTitle(title)
        let singer = firstArtist(artist)
        // By title and artist first; YouTube Music sometimes names artists in a way LRCLIB doesn't,
        // so then by title alone, trusting a hit only if its length matches the song's.
        var records = await search(["track_name": song, "artist_name": singer])
        var needsLengthMatch = false
        if records.isEmpty {
            records = await search(["q": song])
            needsLengthMatch = true
        }
        let close: (Record) -> Bool = { r in
            guard duration > 0, let d = r.duration else { return !needsLengthMatch }
            return abs(d - duration) <= 3
        }
        let candidates = records.filter(close)
        guard let best = candidates.first(where: { $0.syncedLyrics?.isEmpty == false })
                ?? candidates.first(where: { $0.plainLyrics?.isEmpty == false }) else { return nil }
        let lines = parse(best.syncedLyrics ?? "")
        let plain = lines.isEmpty ? (best.plainLyrics ?? "") : ""
        return lines.isEmpty && plain.isEmpty ? nil : (lines, plain)
    }

    /// Tries again a couple of times when the network fails (e.g. just after the Mac wakes).
    private static func search(_ query: [String: String]) async -> [Record] {
        var parts = URLComponents(string: "https://lrclib.net/api/search")!
        parts.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = parts.url else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("P Island \(AppInfo.version) (https://github.com/atikorn-sub/P-Island)", forHTTPHeaderField: "User-Agent")
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(2 * attempt)) }
            if Task.isCancelled { return [] }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let code = (response as? HTTPURLResponse)?.statusCode else { continue }
            if code >= 500 { continue }
            return code == 200 ? (try? JSONDecoder().decode([Record].self, from: data)) ?? [] : []
        }
        return []
    }

    /// "[01:23.45] words" lines; a line can carry several time tags.
    static func parse(_ lrc: String) -> [LyricLine] {
        let tag = #/\[(\d+):(\d+(?:\.\d+)?)\]/#
        var out: [LyricLine] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let tags = line.matches(of: tag)
            guard let last = tags.last else { continue }
            let text = line[last.range.upperBound...].trimmingCharacters(in: .whitespaces)
            for m in tags {
                if let min = Double(m.1), let sec = Double(m.2) {
                    out.append(LyricLine(time: min * 60 + sec, text: text))
                }
            }
        }
        return out.sorted { $0.time < $1.time }
    }

    /// Drops YouTube-style extras: "(Official Video)", "[MV]", "(Lyrics)" and the like.
    private static func cleanTitle(_ title: String) -> String {
        let extras = #/\s*[\(\[][^\)\]]*(official|video|lyric|audio|visuali[sz]er|mv|m\/v)[^\)\]]*[\)\]]/#.ignoresCase()
        let cleaned = title.replacing(extras, with: "").trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? title : cleaned
    }

    /// "A และ B" (YouTube Music in Thai, sometimes without spaces), "A & B", "A, B", "A feat. B" → "A".
    private static func firstArtist(_ artist: String) -> String {
        let joiners = #/\s*(,|&|และ|\sand\s|\sx\s|\sfeat\.?\s|\sft\.?\s)\s{0,}/#.ignoresCase()
        let first = artist.split(separator: joiners, maxSplits: 1).first.map(String.init) ?? artist
        return first.trimmingCharacters(in: .whitespaces)
    }
}
