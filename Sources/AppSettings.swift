import Foundation
import ServiceManagement

final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard
    private var syncingLogin = false

    @Published var haptics: Bool {
        didSet { defaults.set(haptics, forKey: "haptics") }
    }
    @Published var batteryAlerts: Bool {
        didSet { defaults.set(batteryAlerts, forKey: "batteryAlerts") }
    }
    @Published var songPeek: Bool {
        didSet { defaults.set(songPeek, forKey: "songPeek") }
    }
    @Published var volumeHUD: Bool {
        didSet { defaults.set(volumeHUD, forKey: "volumeHUD") }
    }
    @Published var bluetoothAlerts: Bool {
        didSet { defaults.set(bluetoothAlerts, forKey: "bluetoothAlerts") }
    }
    @Published var meetingAlerts: Bool {
        didSet { defaults.set(meetingAlerts, forKey: "meetingAlerts") }
    }
    @Published var clipboardHistory: Bool {
        didSet { defaults.set(clipboardHistory, forKey: "clipboardHistory") }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            guard !syncingLogin, launchAtLogin != oldValue else { return }
            applyLaunchAtLogin()
        }
    }
    /// Scale of the opened notch and alert cards; one of `sizeOptions`.
    @Published var sizeScale: Double {
        didSet { defaults.set(sizeScale, forKey: "sizeScale") }
    }

    static let sizeOptions: [(name: String, scale: Double)] = [
        ("Small", 0.85), ("Default", 1.0), ("Large", 1.15), ("Extra Large", 1.3),
    ]

    init() {
        defaults.register(defaults: [
            "haptics": true, "batteryAlerts": true, "sizeScale": 1.0, "songPeek": true, "volumeHUD": true,
            "bluetoothAlerts": true, "meetingAlerts": true, "clipboardHistory": true,
        ])
        haptics = defaults.bool(forKey: "haptics")
        batteryAlerts = defaults.bool(forKey: "batteryAlerts")
        songPeek = defaults.bool(forKey: "songPeek")
        volumeHUD = defaults.bool(forKey: "volumeHUD")
        bluetoothAlerts = defaults.bool(forKey: "bluetoothAlerts")
        meetingAlerts = defaults.bool(forKey: "meetingAlerts")
        clipboardHistory = defaults.bool(forKey: "clipboardHistory")
        launchAtLogin = SMAppService.mainApp.status == .enabled
        let saved = defaults.double(forKey: "sizeScale")
        sizeScale = Self.sizeOptions.first { abs($0.scale - saved) < 0.01 }?.scale ?? 1.0
    }

    /// Registers again so the login item points at this copy of the app (e.g. after it was renamed or moved).
    func refreshLaunchAtLogin() {
        try? SMAppService.mainApp.unregister()
        do {
            try SMAppService.mainApp.register()
        } catch {
            NSLog("%@", "Islet: launch at login failed: \(error)")
        }
        syncingLogin = true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        syncingLogin = false
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("%@", "Islet: launch at login failed: \(error)")
        }
        let actual = SMAppService.mainApp.status == .enabled
        if actual != launchAtLogin {
            syncingLogin = true
            launchAtLogin = actual
            syncingLogin = false
        }
    }
}
