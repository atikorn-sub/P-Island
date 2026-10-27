import SwiftUI

struct TimerView: View {
    @ObservedObject var timer: TimerManager
    private let presets = [1, 3, 5, 10, 15, 25, 45]

    var body: some View {
        HStack(spacing: 28) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: timer.progress)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: timer.progress)
                VStack(spacing: 0) {
                    Text(TimerManager.format(timer.remaining))
                        .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                    if timer.phase == .finished {
                        Text("Done").font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
                    }
                }
            }
            .frame(width: 130, height: 130)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    ForEach(presets, id: \.self) { m in
                        Button("\(m)m") { timer.setMinutes(m) }
                            .buttonStyle(PillButtonStyle())
                    }
                }
                HStack(spacing: 18) {
                    ControlButton(symbol: "minus", size: 14) { timer.adjust(minutes: -1) }
                    ControlButton(symbol: timer.phase == .running ? "pause.fill" : "play.fill", size: 24) { timer.toggle() }
                    ControlButton(symbol: "arrow.counterclockwise", size: 14) { timer.reset() }
                    ControlButton(symbol: "plus", size: 14) { timer.adjust(minutes: 1) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var ringColor: Color {
        switch timer.phase {
        case .running: return .orange
        case .paused: return .orange.opacity(0.5)
        case .finished: return .green
        case .idle: return .white.opacity(0.3)
        }
    }
}
