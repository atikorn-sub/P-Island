import AppKit
import CoreBluetooth
import EventKit
import Speech
import SwiftUI

enum PermissionState {
    case granted, denied, notAsked, appNotRunning, unknown
}

/// Live status of every permission P Island can use, with the action that fixes each one.
final class PermissionsModel: ObservableObject {
    @Published private(set) var fullDisk: PermissionState = .unknown
    @Published private(set) var calendar: PermissionState = .unknown
    @Published private(set) var bluetooth: PermissionState = .unknown
    @Published private(set) var speech: PermissionState = .unknown
    @Published private(set) var automation: [String: PermissionState] = [:]

    let state: NotchState
    let startBluetooth: () -> Void
    private var timer: Timer?

    /// Apps P Island controls through AppleScript, by bundle ID.
    static let automationTargets: [(id: String, name: String)] = [
        ("com.apple.Music", "Music"),
        ("com.spotify.client", "Spotify"),
        ("com.apple.MobileSMS", "Messages"),
    ]

    init(state: NotchState, startBluetooth: @escaping () -> Void) {
        self.state = state
        self.startBluetooth = startBluetooth
        refresh()
    }

    var missingEssentials: Bool { fullDisk != .granted && state.settings.appNotifications }

    func startWatching() {
        refresh()
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        fullDisk = Self.canRead(NotificationsManager.databasePath) ? .granted : .denied

        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: calendar = .granted
        case .notDetermined: calendar = .notAsked
        default: calendar = .denied
        }

        switch CBManager.authorization {
        case .allowedAlways: bluetooth = .granted
        case .notDetermined: bluetooth = .notAsked
        default: bluetooth = .denied
        }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speech = .granted
        case .notDetermined: speech = .notAsked
        default: speech = .denied
        }

        DispatchQueue.global(qos: .utility).async {
            var result: [String: PermissionState] = [:]
            for target in Self.automationTargets {
                result[target.id] = Self.automationState(target.id, ask: false)
            }
            DispatchQueue.main.async { self.automation = result }
        }
    }

    // MARK: Actions

    func fixFullDisk() {
        open("Privacy_AllFiles")
        // Full Disk Access has no prompt: the app has to be dragged into the list.
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func fixCalendar() {
        calendar == .notAsked ? state.calendar.requestAccess() : open("Privacy_Calendars")
    }

    func fixBluetooth() {
        bluetooth == .notAsked ? startBluetooth() : open("Privacy_Bluetooth")
    }

    func fixSpeech() {
        if speech == .notAsked {
            NSApp.activate(ignoringOtherApps: true)
            SFSpeechRecognizer.requestAuthorization { _ in DispatchQueue.main.async { self.refresh() } }
        } else {
            open("Privacy_SpeechRecognition")
        }
    }

    func fixAutomation(_ bundleID: String) {
        switch automation[bundleID] {
        case .notAsked:
            askAutomation(bundleID)
        case .appNotRunning:
            // The question can only be asked while the app is open, so open it quietly first.
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            config.hides = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.askAutomation(bundleID) }
            }
        default:
            open("Privacy_Automation")
        }
    }

    func openAudioSettings() {
        open("Privacy_ScreenCapture")
    }

    private func askAutomation(_ bundleID: String) {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.global(qos: .userInitiated).async {
            _ = Self.automationState(bundleID, ask: true)
            DispatchQueue.main.async { self.refresh() }
        }
    }

    private func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Checks

    /// A real open() is needed: access() ignores Full Disk Access and would always say yes.
    private static func canRead(_ path: String) -> Bool {
        let fd = Darwin.open(path, O_RDONLY)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }

    /// Blocks while the system asks the user, so call it off the main thread.
    private static func automationState(_ bundleID: String, ask: Bool) -> PermissionState {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil else { return .unknown }
        let target = NSAppleEventDescriptor(bundleIdentifier: bundleID)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, ask)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        case OSStatus(procNotFound): return .appNotRunning
        default: return .unknown
        }
    }
}

/// Every permission with its live status and a button to grant it; the "สิทธิ์การเข้าถึง" settings pane.
struct PermissionsList: View {
    @ObservedObject var model: PermissionsModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            PermissionRow(symbol: "bell.badge.fill", color: .red, title: "Full Disk Access",
                          reason: "แสดงแจ้งเตือนจากแอปอื่น ตอบ iMessage จากรอยบาก และรู้ว่าเปิดโหมด Focus อยู่",
                          hint: model.fullDisk == .granted ? nil
                              : "ลาก P Island จาก Finder ลงในรายการ แล้วเปิดสวิตช์ (ถ้ามีชื่อเดิมอยู่ ให้ลบออกก่อน)",
                          state: model.fullDisk, action: model.fixFullDisk)
            Divider()
            PermissionRow(symbol: "calendar", color: .orange, title: "Calendar",
                          reason: "นัดหมายวันนี้ ปฏิทินรายเดือน และปุ่มเข้าประชุม",
                          state: model.calendar, action: model.fixCalendar)
            Divider()
            PermissionRow(symbol: "airpodspro", color: .blue, title: "Bluetooth",
                          reason: "แจ้งตอน AirPods และอุปกรณ์บลูทูธเชื่อมต่อ พร้อม % แบต",
                          state: model.bluetooth, action: model.fixBluetooth)
            Divider()
            PermissionRow(symbol: "waveform", color: .purple, title: "Speech Recognition",
                          reason: "ถอดเสียงจากไฟล์เสียงหรือวิดีโอบนชั้นวางเป็นข้อความ",
                          state: model.speech, action: model.fixSpeech)
            ForEach(PermissionsModel.automationTargets, id: \.id) { target in
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.id) != nil {
                    Divider()
                    PermissionRow(symbol: "applescript.fill", color: .gray, title: "ควบคุม \(target.name)",
                                  reason: target.id == "com.apple.MobileSMS"
                                      ? "ส่งข้อความตอบกลับ iMessage ที่คุณพิมพ์จากรอยบาก"
                                      : "อ่านเพลงที่กำลังเล่นและกดเล่น/หยุด/ข้ามเพลง",
                                  state: model.automation[target.id] ?? .unknown) {
                        model.fixAutomation(target.id)
                    }
                }
            }
            Divider()
            HStack(spacing: 12) {
                RowIcon(symbol: "chart.bar.fill", color: .green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("System Audio Recording").font(.body.weight(.medium))
                    Text("คลื่นเสียงที่ขยับตามเพลงจริง เปิดสวิตช์แล้วเล่นเพลง macOS จะถามสิทธิ์เอง")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $settings.liveWaveform).toggleStyle(.switch).labelsHidden()
                Button("ตั้งค่า") { model.openAudioSettings() }
            }
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .onAppear { model.startWatching() }
        .onDisappear { model.stopWatching() }
    }
}

struct PermissionRow: View {
    let symbol: String
    let color: Color
    let title: String
    let reason: String
    var hint: String? = nil
    let state: PermissionState
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RowIcon(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.body.weight(.medium))
                    StatusBadge(state: state)
                }
                Text(reason).font(.caption).foregroundStyle(.secondary)
                if let hint {
                    Text(hint).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if state != .granted {
                Button(buttonTitle, action: action)
            }
        }
        .padding(.vertical, 10)
    }

    private var buttonTitle: String {
        switch state {
        case .notAsked: return "อนุญาต"
        case .appNotRunning: return "เปิดแอปแล้วอนุญาต"
        default: return "เปิดการตั้งค่า"
        }
    }
}

struct RowIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(color))
    }
}

struct StatusBadge: View {
    let state: PermissionState

    var body: some View {
        let (text, color): (String, Color) = {
            switch state {
            case .granted: return ("อนุญาตแล้ว", .green)
            case .denied: return ("ยังไม่ได้อนุญาต", .orange)
            case .notAsked: return ("ยังไม่ได้ขอ", .secondary)
            case .appNotRunning: return ("แอปยังไม่เปิด", .secondary)
            case .unknown: return ("—", .secondary)
            }
        }()
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}
