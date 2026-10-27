import SwiftUI

/// The notch dropped down into a card: a row beside the camera, then the message underneath.
struct AlertNotchView: View {
    @ObservedObject var state: NotchState
    let alert: NotchAlert

    var body: some View {
        if case .notification(let note, let replying) = alert {
            NotificationCard(state: state, note: note, replying: replying)
        } else {
            standardCard
        }
    }

    private var standardCard: some View {
        let size = state.closedSize
        let s = state.scale
        return VStack(spacing: 2 * s) {
            HStack(spacing: 0) {
                leading
                Spacer(minLength: state.notchSize.width + 12)
                trailing
            }
            .padding(.horizontal, 22 * s)
            .frame(height: state.notchSize.height)
            content
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .foregroundStyle(.white)
    }

    private var s: CGFloat { state.scale }
    private var rowScale: CGFloat { min(state.scale, 1.1) }

    @ViewBuilder private var leading: some View {
        switch alert {
        case .lowBattery(let level, _), .batteryEstimate(let level, _):
            BatteryGauge(level: level, charging: state.battery.isPluggedIn, width: 28 * rowScale)
        case .fullyCharged:
            BatteryGauge(level: 100, charging: true, width: 28 * rowScale)
        case .nowPlaying:
            NowPlayingThumb(music: state.music, size: state.notchSize.height * 0.62)
        case .volume(let level, let muted):
            Image(systemName: Self.volumeSymbol(level, muted: muted))
                .font(.system(size: 14 * rowScale, weight: .semibold))
        case .brightness:
            Image(systemName: "sun.max.fill")
                .font(.system(size: 14 * rowScale, weight: .semibold))
                .foregroundStyle(.yellow)
        case .meeting:
            Image(systemName: "video.fill")
                .font(.system(size: 14 * rowScale, weight: .semibold))
                .foregroundStyle(.green)
        case .bluetooth(_, let kind, let connected, _):
            Image(systemName: kind.symbol)
                .font(.system(size: 15 * rowScale, weight: .semibold))
                .foregroundStyle(connected ? .white : .white.opacity(0.5))
        case .info(let symbol, _, _):
            Image(systemName: symbol)
                .font(.system(size: 14 * rowScale, weight: .semibold))
                .foregroundStyle(.blue)
        case .notification:
            EmptyView()
        }
    }

    @ViewBuilder private var trailing: some View {
        switch alert {
        case .lowBattery(let level, _), .batteryEstimate(let level, _):
            percent(level, color: BatteryManager.color(for: level))
        case .fullyCharged:
            percent(100, color: .green)
        case .nowPlaying:
            MusicBars(levels: state.audioLevels, color: state.music.accent).frame(height: state.notchSize.height * 0.42)
        case .volume(let level, let muted):
            percent(muted ? 0 : Int((level * 100).rounded()), color: .white)
        case .brightness(let level):
            percent(Int((level * 100).rounded()), color: .white)
        case .meeting(_, _, let start):
            Text(start, format: .dateTime.hour().minute())
                .font(.system(size: 13 * rowScale, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.green)
        case .bluetooth(_, _, let connected, _):
            Image(systemName: connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 15 * rowScale))
                .foregroundStyle(connected ? .blue : .white.opacity(0.5))
        case .info:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15 * rowScale))
                .foregroundStyle(.green)
        case .notification:
            EmptyView()
        }
    }

    @ViewBuilder private var content: some View {
        switch alert {
        case .lowBattery(let level, let minutes):
            message(level <= 10 ? "แบตเตอรี่ใกล้หมด" : "แบตเตอรี่เหลือน้อย",
                    minutes.map { "ใช้งานได้อีกประมาณ \(BatteryManager.formatMinutes($0)) · เสียบสายชาร์จ" }
                        ?? "เสียบสายชาร์จเพื่อใช้งานต่อ",
                    color: BatteryManager.color(for: level))
        case .fullyCharged:
            message("ชาร์จเต็มแล้ว", "ถอดสายชาร์จได้เลย", color: .green)
        case .batteryEstimate(let level, let minutes):
            message("ใช้แบตเตอรี่", "ใช้งานได้อีกประมาณ \(BatteryManager.formatMinutes(minutes))",
                    color: BatteryManager.color(for: level))
        case .nowPlaying(let title, let artist):
            message(title, artist, color: .white)
        case .volume(let level, let muted):
            LevelSlider(value: muted ? 0 : level) { state.controls.setVolume($0) }
                .padding(.horizontal, 22 * s)
        case .brightness(let level):
            LevelSlider(value: level, tint: .yellow) { state.controls.setBrightness($0) }
                .padding(.horizontal, 22 * s)
        case .meeting(let title, let url, _):
            HStack(spacing: 10 * s) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("การประชุมกำลังจะเริ่ม")
                        .font(.system(size: 11 * s))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(title)
                        .font(.system(size: 13 * s, weight: .semibold))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    NSWorkspace.shared.open(url)
                    state.dismissAlert()
                } label: {
                    Text("เข้าร่วม")
                        .font(.system(size: 12 * s, weight: .semibold))
                        .padding(.horizontal, 14 * s)
                        .padding(.vertical, 6 * s)
                        .background(Capsule().fill(Color.green))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22 * s)
        case .bluetooth(let name, _, let connected, let battery):
            message(name, connected ? (battery.map { "เชื่อมต่อแล้ว · \($0)" } ?? "เชื่อมต่อแล้ว") : "ตัดการเชื่อมต่อแล้ว",
                    color: .white)
        case .info(_, let title, let subtitle):
            message(title, subtitle, color: .white)
        case .notification:
            EmptyView()
        }
    }

    private func percent(_ value: Int, color: Color) -> some View {
        Text("\(value)%")
            .font(.system(size: 15 * rowScale, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(color)
    }

    private func message(_ title: String, _ subtitle: String, color: Color) -> some View {
        VStack(spacing: 2 * s) {
            Text(title)
                .font(.system(size: 14 * s, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
            Text(subtitle)
                .font(.system(size: 11 * s))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 22 * s)
    }

    static func volumeSymbol(_ level: Float, muted: Bool) -> String {
        if muted || level == 0 { return "speaker.slash.fill" }
        if level < 0.34 { return "speaker.wave.1.fill" }
        if level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}

/// Artwork of the current song, observed so it fills in when it finishes loading.
struct NowPlayingThumb: View {
    @ObservedObject var music: MusicManager
    let size: CGFloat

    var body: some View {
        ArtworkView(image: music.artwork, trackID: music.trackID, size: size, radius: 6)
    }
}

/// A draggable level bar for volume and brightness.
struct LevelSlider: View {
    let value: Float
    var tint: Color = .white
    let onChange: (Float) -> Void
    @State private var dragValue: Float?

    var body: some View {
        GeometryReader { geo in
            let shown = CGFloat(dragValue ?? value)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(tint).frame(width: max(6, geo.size.width * shown))
            }
            .frame(height: 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let v = Float(min(1, max(0, drag.location.x / geo.size.width)))
                    dragValue = v
                    onChange(v)
                }
                .onEnded { _ in dragValue = nil })
        }
        .frame(height: 16)
    }
}
