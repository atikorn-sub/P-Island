import SwiftUI

struct HomeView: View {
    @ObservedObject var music: MusicManager
    @ObservedObject var calendar: CalendarManager
    @ObservedObject private var lyrics: LyricsManager
    let controls: SystemControls

    init(music: MusicManager, calendar: CalendarManager, controls: SystemControls) {
        self.music = music
        self.calendar = calendar
        self.controls = controls
        lyrics = music.lyrics
    }

    var body: some View {
        // Right column: what plays next, the lyrics and where the sound goes while a song plays;
        // the day's events when nothing does.
        HStack(spacing: 18) {
            NowPlayingCard(music: music)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !music.hasTrack {
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                CalendarCard(calendar: calendar)
                    .frame(width: 180)
            } else {
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                MusicSideColumn(music: music, lyrics: lyrics, controls: controls)
                    .frame(width: 210)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: music.hasTrack)
        .animation(.easeInOut(duration: 0.3), value: music.upNext.isEmpty)
        .animation(.easeInOut(duration: 0.3), value: lyrics.status)
        .onAppear { calendar.reload() }
    }
}

// MARK: - Music

struct NowPlayingCard: View {
    @ObservedObject var music: MusicManager

    var body: some View {
        if music.hasTrack {
            HStack(spacing: 14) {
                ArtworkView(image: music.artwork, trackID: music.trackID, size: 112, radius: 16)
                    .overlay(alignment: .bottomTrailing) { playerBadge }
                    .onTapGesture { music.openPlayer() }
                VStack(alignment: .leading, spacing: 2) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(music.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        Text(music.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { music.openPlayer() }
                    .help(tr("เปิดใน \(music.player?.rawValue ?? "แอปเพลง")", "Open in \(music.player?.rawValue ?? "the player")"))
                    Spacer(minLength: 6)
                    ProgressRow(music: music)
                    controls.padding(.top, 4)
                }
                .frame(maxHeight: 112)
            }
        } else {
            emptyState
        }
    }

    @ViewBuilder private var playerBadge: some View {
        if let url = music.player?.appURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 26, height: 26)
                .offset(x: 6, y: 6)
        }
    }

    private var controls: some View {
        HStack(spacing: 26) {
            ControlButton(symbol: "backward.fill", size: 15) { music.previous() }
            ControlButton(symbol: music.isPlaying ? "pause.fill" : "play.fill", size: 22) { music.togglePlayPause() }
            ControlButton(symbol: "forward.fill", size: 15) { music.next() }
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 28))
                .foregroundStyle(.white.opacity(0.3))
            if let p = music.needsPermission {
                Text(tr("อนุญาตให้ P Island ควบคุม \(p.rawValue)", "Allow P Island to control \(p.rawValue)"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Button(tr("เปิดการตั้งค่า Automation", "Open Automation Settings")) { music.openAutomationSettings() }
                    .buttonStyle(PillButtonStyle())
            } else {
                Text(tr("ไม่มีเพลงที่กำลังเล่น", "Nothing playing"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 8) {
                    ForEach(music.installedPlayers) { p in
                        Button(tr("เปิด \(p.rawValue)", "Open \(p.rawValue)")) { music.openPlayer(p) }
                            .buttonStyle(PillButtonStyle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Up Next and lyrics

/// "Up Next", "Lyrics" and a speaker for the sound output, as small tabs; Up Next and Lyrics only when they have something.
struct MusicSideColumn: View {
    @ObservedObject var music: MusicManager
    @ObservedObject var lyrics: LyricsManager
    let controls: SystemControls
    @AppStorage("homeSideTab") private var chosen = "upNext"

    /// Lyrics found, or still being looked for.
    static func showsLyrics(_ status: LyricsManager.Status) -> Bool {
        status == .synced || status == .plain || status == .loading
    }

    var body: some View {
        let hasQueue = !music.upNext.isEmpty
        let hasLyrics = Self.showsLyrics(lyrics.status)
        let available = (hasQueue ? ["upNext"] : []) + (hasLyrics ? ["lyrics"] : []) + ["output"]
        let tab = available.contains(chosen) ? chosen : available[0]
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if hasQueue { tabButton("upNext", Text(tr("ถัดไป", "Up Next")), selected: tab == "upNext") }
                if hasLyrics { tabButton("lyrics", Text(tr("เนื้อเพลง", "Lyrics")), selected: tab == "lyrics") }
                tabButton("output", Text(Image(systemName: "hifispeaker.fill")), selected: tab == "output")
                    .help(tr("ลำโพงและหูฟัง", "Speakers & headphones"))
            }
            Group {
                if tab == "output" {
                    OutputPicker(controls: controls)
                } else if tab == "lyrics" {
                    LyricsView(music: music, lyrics: lyrics)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 2) {
                            ForEach(music.upNext) { item in
                                UpNextRow(item: item) { music.play(item) }
                            }
                        }
                    }
                }
            }
            .transition(.opacity)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: tab)
    }

    private func tabButton(_ id: String, _ title: Text, selected: Bool) -> some View {
        Button { chosen = id } label: {
            title
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(selected ? 0.95 : 0.45))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.14 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Volume, and the speakers and headphones to choose from; the one playing has a tick.
struct OutputPicker: View {
    @ObservedObject var controls: SystemControls

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: controls.muted || controls.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 16)
                LevelSlider(value: controls.muted ? 0 : controls.volume) { controls.setVolume($0) }
                    .frame(height: 16)
            }
            .padding(.horizontal, 6)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(controls.outputs) { output in
                        OutputRow(output: output, selected: output.id == controls.currentOutput) {
                            controls.setOutput(output)
                        }
                    }
                }
            }
        }
    }
}

private struct OutputRow: View {
    let output: AudioOutput
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: output.symbol)
                    .font(.system(size: 13))
                    .frame(width: 22)
                    .foregroundStyle(selected ? Color.white : Color.white.opacity(0.6))
                Text(output.name)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(selected ? 0.12 : hovering ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Synced lyrics scroll by themselves with the line being sung bright and centred (tap a line to jump
/// there); plain lyrics are just scrollable text.
struct LyricsView: View {
    @ObservedObject var music: MusicManager
    @ObservedObject var lyrics: LyricsManager

    var body: some View {
        switch lyrics.status {
        case .synced:
            TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
                SyncedLyrics(music: music, lines: lyrics.lines, current: lyrics.currentIndex(at: music.position(at: ctx.date)))
            }
        case .plain:
            ScrollView(.vertical, showsIndicators: false) {
                Text(lyrics.plainText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            EmptyView()
        }
    }
}

private struct SyncedLyrics: View {
    let music: MusicManager
    let lines: [LyricLine]
    let current: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                        let isCurrent = i == current
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(isCurrent ? 1 : 0.4))
                            .scaleEffect(isCurrent ? 1.04 : 1, anchor: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentShape(Rectangle())
                            .onTapGesture { music.seek(to: line.time) }
                            .id(i)
                    }
                }
                .padding(.vertical, 50)
                .animation(.easeOut(duration: 0.25), value: current)
            }
            // Lines fade in at the bottom and out at the top.
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.22),
                                         .init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .onChange(of: current) { _, new in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { proxy.scrollTo(new ?? 0, anchor: .center) }
            }
            .onAppear { proxy.scrollTo(current ?? 0, anchor: .center) }
        }
    }
}

private struct UpNextRow: View {
    let item: QueueItem
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                thumbnail
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    Text(item.artist)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if hovering {
                    Image(systemName: "play.fill").font(.system(size: 10))
                } else {
                    Text(item.duration)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.1 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tr("เล่น \(item.title)", "Play \(item.title)"))
    }

    private var thumbnail: some View {
        RemoteCover(url: item.artworkURL)
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// A small cover from the web. Loaded once and kept, so scrolling and hovering never refetch it;
/// a load cut short (the row scrolled away) is simply tried again when the row comes back.
struct RemoteCover: View {
    let url: String
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.white.opacity(0.08)
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            }
        }
        .task(id: url) { image = await CoverCache.shared.image(for: url) }
    }
}

actor CoverCache {
    static let shared = CoverCache()
    private var images: [String: NSImage] = [:]

    func image(for url: String) async -> NSImage? {
        if let cached = images[url] { return cached }
        guard let u = URL(string: url), u.scheme == "https" else { return nil }
        for attempt in 0..<3 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(attempt)) }
            if Task.isCancelled { return nil }
            if let (data, _) = try? await URLSession.shared.data(from: u), let image = NSImage(data: data) {
                if images.count > 200 { images.removeAll() }
                images[url] = image
                return image
            }
        }
        NSLog("%@", "Islet music: cover failed to load: \(url)")
        return nil
    }
}

struct ProgressRow: View {
    @ObservedObject var music: MusicManager
    @State private var dragFraction: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let duration = max(music.duration, 0.001)
            let position = dragFraction.map { $0 * duration } ?? music.position(at: ctx.date)
            VStack(spacing: 3) {
                GeometryReader { geo in
                    let fraction = min(1, max(0, position / duration))
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(music.accent).frame(width: geo.size.width * fraction)
                    }
                    .frame(height: dragFraction == nil ? 5 : 7)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { dragFraction = min(1, max(0, $0.location.x / geo.size.width)) }
                        .onEnded { _ in
                            if let f = dragFraction, music.duration > 0 { music.seek(to: f * music.duration) }
                            dragFraction = nil
                        })
                }
                .frame(height: 10)
                HStack {
                    Text(Self.format(position))
                    Spacer()
                    Text("-" + Self.format(max(0, music.duration - position)))
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            }
        }
        .animation(.easeOut(duration: 0.15), value: dragFraction == nil)
    }

    static func format(_ t: Double) -> String {
        let s = Int(t)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Album art. On a new song it flips over once like a card: the old cover turns edge-on,
/// the new one turns back in with a little bounce.
struct ArtworkView: View {
    let image: NSImage?
    /// Identifies the song; the flip happens once per song, however many times its cover image updates.
    var trackID = ""
    let size: CGFloat
    let radius: CGFloat

    @State private var shown: NSImage?
    @State private var angle: Double = 0
    /// The song whose cover is showing (or is flipping in).
    @State private var flippedFor: String
    @State private var fallback: DispatchWorkItem?

    init(image: NSImage?, trackID: String = "", size: CGFloat, radius: CGFloat) {
        self.image = image
        self.trackID = trackID
        self.size = size
        self.radius = radius
        _shown = State(initialValue: image)
        _flippedFor = State(initialValue: trackID)
    }

    var body: some View {
        Group {
            if let shown {
                Image(nsImage: shown).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    LinearGradient(colors: [Color(white: 0.25), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .onChange(of: trackID) { _, _ in songChanged() }
        .onChange(of: image) { _, new in imageChanged(new) }
    }

    private func songChanged() {
        // Wait for the new cover; if none turns up, turn over to the blank cover.
        fallback?.cancel()
        let song = trackID
        let work = DispatchWorkItem { [self] in
            if flippedFor != song { flip(to: nil) }
        }
        fallback = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    private func imageChanged(_ new: NSImage?) {
        if flippedFor != trackID {
            guard new != nil else { return } // the new song's cover is still loading
            fallback?.cancel()
            flip(to: new)
        } else {
            // Same song, e.g. a sharper copy of the cover arrived: swap quietly, no second flip.
            shown = new
        }
    }

    private func flip(to new: NSImage?) {
        flippedFor = trackID
        guard UserDefaults.standard.bool(forKey: "artworkFlip") else {
            shown = new
            return
        }
        withAnimation(.easeIn(duration: 0.18)) { angle = 90 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            // Swap while edge-on, then come in from the other side.
            shown = new
            angle = -90
            withAnimation(.spring(response: 0.38, dampingFraction: 0.68)) { angle = 0 }
        }
    }
}

struct ControlButton: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .frame(width: size + 16, height: size + 12)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.25 : 0.12)))
    }
}

// MARK: - Calendar

struct CalendarCard: View {
    @ObservedObject var calendar: CalendarManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Date(), format: .dateTime.weekday(.wide))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.red)
                Text(Date(), format: .dateTime.day().month(.abbreviated))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            switch calendar.status {
            case .notDetermined:
                message(tr("ดูนัดหมายวันนี้ที่นี่", "See today's events here"))
                Button(tr("อนุญาตปฏิทิน", "Allow Calendar")) { calendar.requestAccess() }.buttonStyle(PillButtonStyle())
            case .denied:
                message(tr("ยังไม่ได้อนุญาตปฏิทิน", "No calendar access"))
                Button(tr("เปิดการตั้งค่า", "Open Settings")) { calendar.openPrivacySettings() }.buttonStyle(PillButtonStyle())
            case .authorized:
                if calendar.events.isEmpty {
                    message(tr("วันนี้ไม่มีนัดแล้ว", "No more events today"))
                } else {
                    ForEach(calendar.events.prefix(3)) { event in
                        EventRow(event: event)
                    }
                    if calendar.events.count > 3 {
                        message(tr("และอีก \(calendar.events.count - 3) นัด", "+\(calendar.events.count - 3) more"))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
    }
}

struct EventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(nsColor: event.color))
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Group {
                    if event.isAllDay {
                        Text(tr("ทั้งวัน", "All day"))
                    } else {
                        Text(event.start, format: .dateTime.hour().minute()) + Text(" – ") + Text(event.end, format: .dateTime.hour().minute())
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
            if let url = event.meetingURL {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10))
                        .padding(5)
                        .background(Circle().fill(Color.green.opacity(0.8)))
                }
                .buttonStyle(.plain)
                .help(tr("เข้าร่วมประชุม", "Join meeting"))
            }
        }
    }
}
