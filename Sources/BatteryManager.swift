import IOKit.ps
import SwiftUI

enum BatteryEvent {
    case pluggedIn(Int)
    case unplugged(Int)
    /// macOS finished estimating time left after the charger was unplugged.
    case estimate(level: Int, minutes: Int)
    case low(Int)
    case full
}

final class BatteryManager: ObservableObject {
    @Published private(set) var level = 100
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var hasBattery = false
    /// From IOKit; nil while macOS is still estimating.
    @Published private(set) var minutesToEmpty: Int?
    @Published private(set) var minutesToFull: Int?

    var onEvent: ((BatteryEvent) -> Void)?

    static let lowThresholds = [20, 10, 5]

    private var source: CFRunLoopSource?
    private var awaitingEstimate = false

    init() {
        refresh(initial: true)
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<BatteryManager>.fromOpaque(context).takeUnretainedValue().refresh(initial: false)
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    var color: Color { Self.color(for: level) }

    /// Green above 50 %, orange down to 21 %, red at 20 % and below.
    static func color(for level: Int) -> Color {
        if level > 50 { return .green }
        if level > 20 { return .orange }
        return .red
    }

    /// e.g. "1 ชม. 20 นาที" or "25 นาที".
    static func formatMinutes(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return tr("\(m) นาที", "\(m) min") }
        return m == 0 ? tr("\(h) ชม.", "\(h) hr") : tr("\(h) ชม. \(m) นาที", "\(h) hr \(m) min")
    }

    private func refresh(initial: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let newLevel = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : 0
            let plugged = desc[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            let toEmpty = (desc[kIOPSTimeToEmptyKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
            let toFull = (desc[kIOPSTimeToFullChargeKey] as? Int).flatMap { $0 > 0 ? $0 : nil }
            let oldLevel = level
            let wasPlugged = isPluggedIn

            hasBattery = true
            if level != newLevel { level = newLevel }
            if isCharging != charging { isCharging = charging }
            if isPluggedIn != plugged { isPluggedIn = plugged }
            if minutesToEmpty != toEmpty { minutesToEmpty = toEmpty }
            if minutesToFull != toFull { minutesToFull = toFull }

            guard !initial else { return }
            if plugged {
                awaitingEstimate = false
            } else if awaitingEstimate, let toEmpty {
                awaitingEstimate = false
                onEvent?(.estimate(level: newLevel, minutes: toEmpty))
            }
            if plugged && !wasPlugged {
                onEvent?(.pluggedIn(newLevel))
            } else if !plugged && wasPlugged {
                onEvent?(.unplugged(newLevel))
                // The estimate usually arrives a few seconds later.
                if let toEmpty {
                    onEvent?(.estimate(level: newLevel, minutes: toEmpty))
                } else {
                    awaitingEstimate = true
                }
            } else if !plugged, Self.lowThresholds.contains(where: { oldLevel > $0 && newLevel <= $0 }) {
                onEvent?(.low(newLevel))
            } else if plugged, oldLevel < 100, newLevel == 100 {
                onEvent?(.full)
            }
            return
        }
    }
}
