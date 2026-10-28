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
    @Published var appNotifications: Bool {
        didSet { defaults.set(appNotifications, forKey: "appNotifications") }
    }
    /// Off by default: turning it on asks for the System Audio Recording permission.
    @Published var liveWaveform: Bool {
        didSet { defaults.set(liveWaveform, forKey: "liveWaveform") }
    }
    /// "wings" (art and bars beside the camera) or "mini" (a slim player bar across the menu bar) while music plays.
    @Published var closedStyle: String {
        didSet { defaults.set(closedStyle, forKey: "closedStyle") }
    }
    /// "black" or "glass": how the open panel and drop-down cards look. The closed notch is always black.
    @Published var notchStyle: String {
        didSet { defaults.set(notchStyle, forKey: "notchStyle") }
    }
    /// Darkness of the glass, 0 … 0.7.
    @Published var glassTint: Double {
        didSet { defaults.set(glassTint, forKey: "glassTint") }
    }
    /// Soft light in the cover's colours behind the open panel (black look).
    @Published var ambientGlow: Bool {
        didSet { defaults.set(ambientGlow, forKey: "ambientGlow") }
    }
    /// Time-synced lyrics from LRCLIB beside the player.
    @Published var lyrics: Bool {
        didSet { defaults.set(lyrics, forKey: "lyrics") }
    }
    /// The line being sung replaces the song name in the slim bar.
    @Published var lyricsInSlimBar: Bool {
        didSet { defaults.set(lyricsInSlimBar, forKey: "lyricsInSlimBar") }
    }
    /// Look for a newer P Island on GitHub once a day.
    @Published var checkUpdates: Bool {
        didSet { defaults.set(checkUpdates, forKey: "checkUpdates") }
    }
    /// Live activities on the closed notch.
    @Published var liveDownloads: Bool {
        didSet { defaults.set(liveDownloads, forKey: "liveDownloads") }
    }
    @Published var liveCameraMic: Bool {
        didSet { defaults.set(liveCameraMic, forKey: "liveCameraMic") }
    }
    /// Counting down to the next event in the last ten minutes before it.
    @Published var liveMeetingCountdown: Bool {
        didSet { defaults.set(liveMeetingCountdown, forKey: "liveMeetingCountdown") }
    }
    @Published var liveCapsLock: Bool {
        didSet { defaults.set(liveCapsLock, forKey: "liveCapsLock") }
    }
    /// Album art flips over when the song changes (read by ArtworkView straight from UserDefaults).
    @Published var artworkFlip: Bool {
        didSet { defaults.set(artworkFlip, forKey: "artworkFlip") }
    }
    /// While a Focus is on, hold back app notifications, song peeks and Bluetooth cards.
    @Published var respectFocus: Bool {
        didSet { defaults.set(respectFocus, forKey: "respectFocus") }
    }
    @Published var showPermissionsAtLaunch: Bool {
        didSet { defaults.set(showPermissionsAtLaunch, forKey: "showPermissionsAtLaunch") }
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

    static var sizeOptions: [(name: String, scale: Double)] { [
        (tr("เล็ก", "Small"), 0.85), (tr("ปกติ", "Default"), 1.0), (tr("ใหญ่", "Large"), 1.15), (tr("ใหญ่มาก", "Extra Large"), 1.3),
    ] }

    /// The app's language; also mirrored into `Lang.setting`, which `tr()` reads.
    @Published var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: "language")
            Lang.setting = language
        }
    }

    init() {
        // First, so every tr() from here on speaks the right language.
        let savedLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .system
        Lang.setting = savedLanguage
        language = savedLanguage
        defaults.register(defaults: [
            "haptics": true, "batteryAlerts": true, "sizeScale": 1.0, "songPeek": true, "volumeHUD": true,
            "bluetoothAlerts": true, "meetingAlerts": true, "clipboardHistory": true,
            "appNotifications": true, "liveWaveform": false, "showPermissionsAtLaunch": true, "respectFocus": true,
            "artworkFlip": true, "notchStyle": "black", "glassTint": 0.25, "closedStyle": "wings", "ambientGlow": true,
            "lyrics": true, "lyricsInSlimBar": true, "checkUpdates": true,
            "liveDownloads": true, "liveCameraMic": true, "liveCapsLock": true, "liveMeetingCountdown": true,
        ])
        notchStyle = defaults.string(forKey: "notchStyle") ?? "black"
        closedStyle = defaults.string(forKey: "closedStyle") ?? "wings"
        ambientGlow = defaults.bool(forKey: "ambientGlow")
        lyrics = defaults.bool(forKey: "lyrics")
        lyricsInSlimBar = defaults.bool(forKey: "lyricsInSlimBar")
        checkUpdates = defaults.bool(forKey: "checkUpdates")
        liveDownloads = defaults.bool(forKey: "liveDownloads")
        liveCameraMic = defaults.bool(forKey: "liveCameraMic")
        liveCapsLock = defaults.bool(forKey: "liveCapsLock")
        liveMeetingCountdown = defaults.bool(forKey: "liveMeetingCountdown")
        glassTint = defaults.double(forKey: "glassTint")
        artworkFlip = defaults.bool(forKey: "artworkFlip")
        respectFocus = defaults.bool(forKey: "respectFocus")
        showPermissionsAtLaunch = defaults.bool(forKey: "showPermissionsAtLaunch")
        appNotifications = defaults.bool(forKey: "appNotifications")
        liveWaveform = defaults.bool(forKey: "liveWaveform")
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
