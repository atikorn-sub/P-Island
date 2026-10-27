import SwiftUI

/// Battery outline filled to the exact level, coloured green / orange / red.
struct BatteryGauge: View {
    let level: Int
    var charging = false
    var width: CGFloat = 25

    var body: some View {
        let height = width * 0.48
        let color = BatteryManager.color(for: level)
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
                RoundedRectangle(cornerRadius: height * 0.18, style: .continuous)
                    .fill(color)
                    .frame(width: max(2, (width - 4) * CGFloat(min(level, 100)) / 100))
                    .padding(2)
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: height * 0.75, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 1)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: width, height: height)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.45))
                .frame(width: 1.5, height: height * 0.38)
        }
    }
}
