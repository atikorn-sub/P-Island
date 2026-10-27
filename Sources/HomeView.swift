import SwiftUI

struct HomeView: View {
    @ObservedObject var music: MusicManager
    @ObservedObject var calendar: CalendarManager

    var body: some View {
        HStack(spacing: 18) {
            NowPlayingCard(music: music)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
            CalendarCard(calendar: calendar)
                .frame(width: 180)
        }
        .onAppear { calendar.reload() }
    }
}

// MARK: - Music

struct NowPlayingCard: View {
    @ObservedObject var music: MusicManager

    var body: some View {
        if music.hasTrack {
            HStack(spacing: 14) {
                ArtworkView(image: music.artwork, size: 112, radius: 16)
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
                    .help("เปิดใน \(music.player?.rawValue ?? "แอปเพลง")")
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
                Text("อนุญาตให้ P Island ควบคุม \(p.rawValue)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Button("เปิดการตั้งค่า Automation") { music.openAutomationSettings() }
                    .buttonStyle(PillButtonStyle())
            } else {
                Text("ไม่มีเพลงที่กำลังเล่น")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 8) {
                    ForEach(music.installedPlayers) { p in
                        Button("เปิด \(p.rawValue)") { music.openPlayer(p) }
                            .buttonStyle(PillButtonStyle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat
    let radius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
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
                message("ดูนัดหมายวันนี้ที่นี่")
                Button("อนุญาตปฏิทิน") { calendar.requestAccess() }.buttonStyle(PillButtonStyle())
            case .denied:
                message("ยังไม่ได้อนุญาตปฏิทิน")
                Button("เปิดการตั้งค่า") { calendar.openPrivacySettings() }.buttonStyle(PillButtonStyle())
            case .authorized:
                if calendar.events.isEmpty {
                    message("วันนี้ไม่มีนัดแล้ว")
                } else {
                    ForEach(calendar.events.prefix(3)) { event in
                        EventRow(event: event)
                    }
                    if calendar.events.count > 3 {
                        message("และอีก \(calendar.events.count - 3) นัด")
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
                        Text("ทั้งวัน")
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
                .help("เข้าร่วมประชุม")
            }
        }
    }
}
