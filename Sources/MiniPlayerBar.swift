import SwiftUI

/// The closed notch stretched into a slim player across the menu bar:
/// cover and song on the left of the camera, time, progress and controls on the right.
struct MiniPlayerBar: View {
    @ObservedObject var state: NotchState
    @ObservedObject private var music: MusicManager
    @ObservedObject private var timer: TimerManager

    init(state: NotchState) {
        self.state = state
        music = state.music
        timer = state.timer
    }

    var body: some View {
        let h = state.notchSize.height
        let wing = state.miniWingWidth
        HStack(spacing: 0) {
            HStack(spacing: 7) {
                ArtworkView(image: music.artwork, trackID: music.trackID, size: h * 0.6, radius: 4)
                Text(music.artist.isEmpty ? music.title : "\(music.title) — \(music.artist)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .frame(width: wing, height: h)
            .contentShape(Rectangle())
            .onTapGesture { state.openPanel?() }
            .help(tr("คลิกเพื่อกางรอยบาก", "Click to open the notch"))

            Color.clear.frame(width: state.notchSize.width, height: h)

            HStack(spacing: 8) {
                if timer.isActive {
                    Text(TimerManager.format(timer.remaining))
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.orange)
                }
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let position = music.position(at: ctx.date)
                    HStack(spacing: 6) {
                        Text(ProgressRow.format(position))
                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.6))
                        MiniProgress(fraction: music.duration > 0 ? position / music.duration : 0, color: music.accent)
                    }
                }
                MiniButton(symbol: music.isPlaying ? "pause.fill" : "play.fill") { music.togglePlayPause() }
                MiniButton(symbol: "forward.fill") { music.next() }
            }
            .padding(.trailing, 10)
            .frame(width: wing, height: h)
        }
        .padding(.horizontal, NotchState.closedTopRadius)
        .frame(width: state.closedSize.width, height: h)
        .foregroundStyle(.white)
    }
}

private struct MiniProgress: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule().fill(color).frame(width: geo.size.width * CGFloat(min(1, max(0, fraction))))
            }
        }
        .frame(minWidth: 36, maxWidth: .infinity)
        .frame(height: 3)
    }
}

private struct MiniButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.15 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
