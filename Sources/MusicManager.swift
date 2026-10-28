import AppKit
import CoreImage
import SwiftUI

enum PlayerCommand {
    case playPause, next, previous, focus
    case seek(Double)
    /// Jump to a song in the queue: its position there, and its title as a check.
    case playItem(index: Int, title: String)
}

/// A song waiting after the current one.
struct QueueItem: Identifiable, Equatable {
    var id: String { "\(index)|\(title)" }
    let index: Int
    let title: String
    let artist: String
    let artworkURL: String
    let duration: String
}

enum MusicPlayer: String, CaseIterable, Identifiable {
    case music = "Music"
    case spotify = "Spotify"
    case youtubeMusic = "YouTube Music"

    var id: String { rawValue }

    /// The app that has to be running (YouTube Music lives in a Chrome tab).
    var bundleID: String {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        case .youtubeMusic: return "com.google.Chrome"
        }
    }

    /// Posted by the player whenever the track or play state changes.
    /// YouTube Music reports through `YouTubeMusicBridge` instead.
    var changeNotification: Notification.Name? {
        switch self {
        case .music: return Notification.Name("com.apple.Music.playerInfo")
        case .spotify: return Notification.Name("com.spotify.client.PlaybackStateChanged")
        case .youtubeMusic: return nil
        }
    }

    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }
    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }

    /// Returns {state} when stopped, otherwise {state, title, artist, album, duration (s), position (s), artwork url}.
    /// Only used for the AppleScript players.
    var stateScript: String {
        switch self {
        case .music:
            return """
            tell application "Music"
                set s to player state as text
                if s is "stopped" then return {s}
                try
                    set t to current track
                    return {s, name of t, artist of t, album of t, duration of t, player position, ""}
                on error
                    try
                        return {s, current stream title, "", "", 0, 0, ""}
                    end try
                end try
                return {s}
            end tell
            """
        case .spotify:
            return """
            tell application "Spotify"
                set s to player state as text
                if s is "stopped" then return {s}
                set t to current track
                return {s, name of t, artist of t, album of t, (duration of t) / 1000, player position, artwork url of t}
            end tell
            """
        case .youtubeMusic:
            return ""
        }
    }

    /// AppleScript for Music / Spotify commands.
    func script(for command: PlayerCommand) -> String {
        let verb: String
        switch command {
        case .playPause: verb = "playpause"
        case .next: verb = "next track"
        case .previous: verb = "previous track"
        case .focus: verb = "activate"
        case .seek(let s): verb = "set player position to \(String(format: "%.2f", s))"
        case .playItem(let index, _): verb = "play track \(index) of current playlist"
        }
        return "tell application \"\(rawValue)\" to \(verb)"
    }
}

private struct PlayerSnapshot {
    var player: MusicPlayer
    var playing: Bool
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var artworkURL: String
    /// What plays next, when the player says it here (YouTube Music); nil means ask separately.
    var queue: [QueueItem]?
}

private struct ScriptResult {
    var descriptor: NSAppleEventDescriptor?
    var errorNumber: Int?
    var errorMessage: String?
}

/// Reads and controls Music and Spotify through AppleScript (needs the Automation permission once),
/// and YouTube Music through the Islet Chrome extension.
final class MusicManager: ObservableObject {
    @Published private(set) var player: MusicPlayer?
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var isPlaying = false {
        didSet {
            guard isPlaying != oldValue else { return }
            pausedAt = isPlaying ? nil : Date()
            if !isPlaying {
                // Let views re-check `recentlyPaused` once the grace period is over.
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.pauseGrace + 0.1) { [weak self] in
                    self?.objectWillChange.send()
                }
            }
        }
    }
    private var pausedAt: Date?
    static let pauseGrace: TimeInterval = 30
    /// Paused within the last 30 s (the slim bar stays out so play is one click away).
    var recentlyPaused: Bool { pausedAt.map { Date().timeIntervalSince($0) < Self.pauseGrace } ?? false }
    @Published private(set) var duration: Double = 0
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = .white
    /// The cover, tiny and heavily blurred: the colours behind the panel's ambient glow.
    @Published private(set) var ambientImage: NSImage?
    @Published private(set) var needsPermission: MusicPlayer?
    /// Songs after the current one: YouTube Music's queue, or the rest of Music's playlist. Empty for Spotify.
    @Published private(set) var upNext: [QueueItem] = []

    /// Called with (title, artist) when a new song starts playing (not for the song found at launch).
    var onTrackChange: ((String, String) -> Void)?

    private var elapsed: Double = 0
    private var hasApplied = false
    private var elapsedAt = Date()
    private var artworkKey: String?
    private var queueKey: String?
    private var pollWork: DispatchWorkItem?

    private let youtube = YouTubeMusicBridge()
    private let queue = DispatchQueue(label: "islet.music", qos: .userInitiated)
    private var scripts: [String: NSAppleScript] = [:] // only touched on `queue`

    var hasTrack: Bool { player != nil && !title.isEmpty }
    /// Changes exactly when the song changes (used to flip the cover once per song).
    var trackID: String { "\(player?.rawValue ?? "")|\(title)|\(artist)" }
    var installedPlayers: [MusicPlayer] { MusicPlayer.allCases.filter { $0.appURL != nil } }

    init() {
        for p in MusicPlayer.allCases {
            guard let name = p.changeNotification else { continue }
            DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh(after: 0.15)
            }
        }
        youtube.onChange = { [weak self] in self?.refresh(after: 0.05) }
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh(after: 1.5)
        }
        refresh()
    }

    func position(at date: Date) -> Double {
        guard duration > 0 else { return 0 }
        let moved = isPlaying ? date.timeIntervalSince(elapsedAt) : 0
        return min(duration, max(0, elapsed + moved))
    }

    // MARK: Controls

    func togglePlayPause() {
        guard let p = player else { return }
        elapsed = position(at: Date())
        elapsedAt = Date()
        isPlaying.toggle()
        send(p, .playPause)
    }

    func next() {
        guard let p = player else { return }
        send(p, .next)
    }

    func previous() {
        guard let p = player else { return }
        send(p, .previous)
    }

    func seek(to seconds: Double) {
        guard let p = player else { return }
        elapsed = seconds
        elapsedAt = Date()
        objectWillChange.send()
        send(p, .seek(seconds))
    }

    func play(_ item: QueueItem) {
        guard let p = player else { return }
        // Drop it and what came before from the list straight away; the player confirms shortly.
        upNext.removeAll { $0.index <= item.index }
        send(p, .playItem(index: item.index, title: item.title))
    }

    /// With an explicit player (the "Open …" buttons) YouTube Music opens in Chrome; otherwise brings the
    /// current player forward — for YouTube Music, the very tab that is playing.
    func openPlayer(_ p: MusicPlayer? = nil) {
        guard let target = p ?? player, let appURL = target.appURL else { return }
        if target == .youtubeMusic, p != nil, let url = URL(string: "https://music.youtube.com") {
            NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            return
        }
        if target == .youtubeMusic { youtube.send(.focus) }
        NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    private func send(_ p: MusicPlayer, _ command: PlayerCommand) {
        if p == .youtubeMusic {
            youtube.send(command)
            refresh(after: 0.6)
            return
        }
        let source = p.script(for: command)
        queue.async {
            _ = self.run(source, cache: false)
            DispatchQueue.main.async { self.refresh(after: 0.3) }
        }
    }

    // MARK: Polling

    func refresh(after delay: Double = 0) {
        pollWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.poll() }
        pollWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func poll() {
        // Only talk to players that are already open, so polling never launches them.
        let running = MusicPlayer.allCases.filter(\.isRunning)
        let current = player
        queue.async {
            var snapshots: [PlayerSnapshot] = []
            var denied: MusicPlayer?
            for p in running {
                if p == .youtubeMusic {
                    if let snap = self.youtubeSnapshot() { snapshots.append(snap) }
                    continue
                }
                let result = self.run(p.stateScript)
                self.logIfChanged(p, result)
                if result.errorNumber == -1743 { denied = p }
                if let desc = result.descriptor, let snap = Self.parse(desc, player: p) { snapshots.append(snap) }
            }
            let chosen = snapshots.first(where: \.playing)
                ?? snapshots.first(where: { $0.player == current })
                ?? snapshots.first
            DispatchQueue.main.async {
                if self.needsPermission != denied { self.needsPermission = denied }
                self.apply(chosen)
                self.refresh(after: chosen?.playing == true ? 2 : 5)
            }
        }
    }

    private func youtubeSnapshot() -> PlayerSnapshot? {
        guard let (s, receivedAt) = youtube.current(), !s.title.isEmpty else { return nil }
        let position = s.position + (s.playing ? Date().timeIntervalSince(receivedAt) : 0)
        return PlayerSnapshot(player: .youtubeMusic, playing: s.playing, title: s.title, artist: s.artist,
                              album: s.album, duration: s.duration, position: position, artworkURL: s.artwork,
                              queue: (s.queue ?? []).map {
                                  QueueItem(index: $0.index, title: $0.title, artist: $0.artist,
                                            artworkURL: $0.artwork, duration: $0.duration)
                              })
    }

    private static func parse(_ desc: NSAppleEventDescriptor, player: MusicPlayer) -> PlayerSnapshot? {
        guard desc.numberOfItems >= 7 else { return nil }
        func text(_ i: Int) -> String { desc.atIndex(i)?.stringValue ?? "" }
        func number(_ i: Int) -> Double { desc.atIndex(i)?.doubleValue ?? 0 }
        let title = text(2)
        guard !title.isEmpty else { return nil }
        return PlayerSnapshot(player: player, playing: text(1) == "playing", title: title,
                              artist: text(3), album: text(4), duration: number(5),
                              position: number(6), artworkURL: text(7))
    }

    private func apply(_ s: PlayerSnapshot?) {
        defer { hasApplied = true }
        if let s, s.playing, hasApplied, s.title != title || s.player != player {
            onTrackChange?(s.title, s.artist)
        }
        guard let s else {
            if player != nil {
                player = nil
                title = ""
                artist = ""
                album = ""
                isPlaying = false
                duration = 0
                artwork = nil
                ambientImage = nil
                accent = .white
                artworkKey = nil
                upNext = []
                queueKey = nil
            }
            return
        }
        if player != s.player { player = s.player }
        if title != s.title { title = s.title }
        if artist != s.artist { artist = s.artist }
        if album != s.album { album = s.album }
        if isPlaying != s.playing { isPlaying = s.playing }
        if duration != s.duration { duration = s.duration }
        elapsed = s.position
        elapsedAt = Date()

        let key = "\(s.player.rawValue)|\(s.title)|\(s.album)|\(s.artworkURL)"
        if key != artworkKey {
            artworkKey = key
            loadArtwork(for: s, key: key)
        }
        updateQueue(from: s)
    }

    private func updateQueue(from s: PlayerSnapshot) {
        if let queue = s.queue {
            if upNext != queue { upNext = queue }
            return
        }
        // Music: read the playlist once per song.
        let key = "\(s.player.rawValue)|\(s.title)|\(s.artist)"
        guard key != queueKey else { return }
        queueKey = key
        guard s.player == .music else {
            if !upNext.isEmpty { upNext = [] }
            return
        }
        queue.async {
            let items = self.run(Self.musicQueueScript).descriptor.map(Self.parseQueue) ?? []
            DispatchQueue.main.async {
                guard self.queueKey == key else { return }
                if self.upNext != items { self.upNext = items }
            }
        }
    }

    /// The next 25 tracks of the playlist Music is playing from, as {index, name, artist, duration}.
    /// Nothing while Shuffle is on, since the playlist order isn't the play order then.
    private static let musicQueueScript = """
    tell application "Music"
        if shuffle enabled then return {}
        set p to current playlist
        set i to index of current track
        set n to count of tracks of p
        set stopAt to i + 25
        if stopAt > n then set stopAt to n
        set out to {}
        repeat with k from (i + 1) to stopAt
            set t to track k of p
            set end of out to {k, name of t, artist of t, duration of t}
        end repeat
        return out
    end tell
    """

    private static func parseQueue(_ desc: NSAppleEventDescriptor) -> [QueueItem] {
        guard desc.numberOfItems > 0 else { return [] }
        return (1...desc.numberOfItems).compactMap { i in
            guard let row = desc.atIndex(i), row.numberOfItems >= 4,
                  let title = row.atIndex(2)?.stringValue, !title.isEmpty else { return nil }
            let seconds = row.atIndex(4)?.doubleValue ?? 0
            return QueueItem(index: Int(row.atIndex(1)?.int32Value ?? 0), title: title,
                             artist: row.atIndex(3)?.stringValue ?? "", artworkURL: "",
                             duration: seconds > 0 ? ProgressRow.format(seconds) : "")
        }
    }

    private func loadArtwork(for s: PlayerSnapshot, key: String) {
        let finish: (NSImage?) -> Void = { [weak self] image in
            DispatchQueue.main.async {
                guard let self, self.artworkKey == key else { return }
                self.artwork = image
                self.accent = image.flatMap(Self.accentColor).map { Color(nsColor: $0) } ?? .white
                self.ambientImage = image.flatMap(Self.ambient)
            }
        }
        switch s.player {
        case .music:
            queue.async {
                let result = self.run("tell application \"Music\" to get raw data of artwork 1 of current track")
                finish(result.descriptor.flatMap { NSImage(data: $0.data) })
            }
        case .spotify, .youtubeMusic:
            guard let url = URL(string: s.artworkURL), url.scheme == "https" else { return finish(nil) }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                finish(data.flatMap { NSImage(data: $0) })
            }.resume()
        }
    }

    /// Shrinks the cover to 48 px, blurs and saturates it once; the glow then only moves it around.
    private static func ambient(_ image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let small = CIImage(cgImage: cg)
            .transformed(by: CGAffineTransform(scaleX: 48 / CGFloat(cg.width), y: 48 / CGFloat(cg.height)))
        let blurred = small.clampedToExtent()
            .applyingGaussianBlur(sigma: 6)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 2.1, kCIInputBrightnessKey: 0.08, kCIInputContrastKey: 1.15])
            .cropped(to: CGRect(x: 0, y: 0, width: 48, height: 48))
        guard let out = CIContext().createCGImage(blurred, from: blurred.extent) else { return nil }
        return NSImage(cgImage: out, size: NSSize(width: 48, height: 48))
    }

    /// Average artwork colour, brightened so it reads on black.
    private static func accentColor(_ image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = pixel.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        let c = NSColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        var h: CGFloat = 0, sat: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &sat, brightness: &b, alpha: &a)
        return NSColor(hue: h, saturation: min(1, sat * 1.3), brightness: max(b, 0.75), alpha: 1)
    }

    private var lastLogged: [MusicPlayer: String] = [:] // only touched on `queue`

    /// Logs each player's poll outcome when it changes: `log show --predicate 'eventMessage CONTAINS "Islet music"'`.
    private func logIfChanged(_ p: MusicPlayer, _ result: ScriptResult) {
        let line: String
        if let n = result.errorNumber {
            line = "error \(n): \(result.errorMessage ?? "")"
        } else {
            let value = result.descriptor?.stringValue ?? "<\(result.descriptor?.numberOfItems ?? 0) items>"
            line = "ok: \(value.isEmpty ? "(no track)" : String(value.prefix(160)))"
        }
        guard lastLogged[p] != line else { return }
        lastLogged[p] = line
        NSLog("%@", "Islet music [\(p.rawValue)] \(line)")
    }

    /// Runs an AppleScript on `queue`. Polling scripts are compiled once and cached.
    private func run(_ source: String, cache: Bool = true) -> ScriptResult {
        let script: NSAppleScript
        if let cached = scripts[source] {
            script = cached
        } else {
            guard let made = NSAppleScript(source: source) else { return ScriptResult() }
            if cache { scripts[source] = made }
            script = made
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            return ScriptResult(errorNumber: error[NSAppleScript.errorNumber] as? Int,
                                errorMessage: error[NSAppleScript.errorMessage] as? String)
        }
        return ScriptResult(descriptor: result)
    }
}
