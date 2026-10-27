import SwiftUI

/// Soft light in the cover's colours behind the open panel, like Apple Music's ambient mode.
/// The image is already tiny and blurred, so the slow drift costs next to nothing.
struct AmbientGlow: View {
    @ObservedObject var music: MusicManager

    var body: some View {
        if let image = music.ambientImage {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !music.isPlaying)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                GeometryReader { geo in
                    let side = max(geo.size.width, geo.size.height) * 0.85
                    ZStack {
                        blob(image, side: side)
                            .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 120) * 3))
                            .offset(x: -geo.size.width * 0.25 + sin(t * 0.25) * 40, y: geo.size.height * 0.2)
                            .opacity(0.95)
                        blob(image, side: side * 0.7)
                            .scaleEffect(x: -1, y: 1)
                            .rotationEffect(.degrees(-t.truncatingRemainder(dividingBy: 180) * 2))
                            .offset(x: geo.size.width * 0.28 + cos(t * 0.2) * 40, y: -geo.size.height * 0.15)
                            .opacity(0.8)
                            .blendMode(.screen)
                        // Keep text readable: darker at the bottom and over the header.
                        LinearGradient(colors: [.black.opacity(0.3), .black.opacity(0.05), .black.opacity(0.4)],
                                       startPoint: .top, endPoint: .bottom)
                        // Vignette: the light pools in the middle and fades into black at the edges.
                        RadialGradient(colors: [.clear, .black.opacity(0.7)], center: .center,
                                       startRadius: geo.size.height * 0.3, endRadius: geo.size.width * 0.6)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.8), value: music.trackID)
        }
    }

    private func blob(_ image: NSImage, side: CGFloat) -> some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
            .blur(radius: 24)
    }
}
