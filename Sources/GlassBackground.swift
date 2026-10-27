import SwiftUI

/// What sits behind the notch's content: plain black (blends with the camera housing) or glass.
/// On macOS 26 and later the glass is Apple's own Liquid Glass; before that it is a blur with a
/// highlight and a bright rim that looks close to it.
struct NotchBackground: View {
    let shape: NotchShape
    let glass: Bool
    let notchSize: CGSize
    /// Only a real notch needs the black island drawn in; screens without one stay all glass.
    let hasNotch: Bool
    /// How dark the glass is, 0 (clear) … 0.7 (smoky).
    let tint: Double

    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(Color.black).opacity(glass ? 0 : 1)
            if glass {
                glassLayer
                    .transition(.opacity)
                if hasNotch {
                    // The camera housing is black whatever we draw, so make it part of the design.
                    UnevenRoundedRectangle(bottomLeadingRadius: notchSize.height * 0.3,
                                           bottomTrailingRadius: notchSize.height * 0.3,
                                           style: .continuous)
                        .fill(Color.black)
                        .frame(width: notchSize.width, height: notchSize.height)
                }
            }
        }
    }

    @ViewBuilder private var glassLayer: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular.tint(Color.black.opacity(tint)), in: shape)
        } else {
            ZStack {
                BehindWindowBlur()
                Color.black.opacity(tint)
                // Light catching the top edge.
                LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.03), .clear],
                               startPoint: .top, endPoint: .bottom)
            }
            .clipShape(shape)
            .overlay(
                shape.stroke(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08), .white.opacity(0.28)],
                                            startPoint: .topLeading, endPoint: .bottomTrailing),
                             lineWidth: 1.2)
            )
        }
    }
}

/// Frosted blur of whatever is behind the window (wallpaper, apps, menu bar).
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active // the notch panel is never the key window; keep the blur on regardless
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
