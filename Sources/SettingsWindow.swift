import Combine
import SwiftUI

enum AppInfo {
    static let name = "P Island"
    static let developer = "Atikorn Subsuieng"
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, alerts, music, calendar, clipboard, permissions, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return tr("ทั่วไป", "General")
        case .alerts: return tr("การแจ้งเตือน", "Notifications")
        case .music: return tr("เพลง", "Music")
        case .calendar: return tr("ปฏิทินและอากาศ", "Calendar & Weather")
        case .clipboard: return tr("คลิปบอร์ด", "Clipboard")
        case .permissions: return tr("สิทธิ์การเข้าถึง", "Permissions")
        case .about: return tr("เกี่ยวกับ", "About")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .alerts: return "bell.badge.fill"
        case .music: return "music.note"
        case .calendar: return "calendar"
        case .clipboard: return "doc.on.clipboard.fill"
        case .permissions: return "lock.shield.fill"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return .gray
        case .alerts: return .red
        case .music: return .pink
        case .calendar: return .orange
        case .clipboard: return .teal
        case .permissions: return .blue
        case .about: return .indigo
        }
    }
}

final class SettingsSelection: ObservableObject {
    @Published var pane: SettingsPane? = .general
}

/// One window for every setting, one category at a time, like System Settings.
final class SettingsWindowController: NSObject {
    private let state: NotchState
    private let permissions: PermissionsModel
    private let selection = SettingsSelection()
    private var window: NSWindow?
    private var languageObserver: AnyCancellable?

    init(state: NotchState, permissions: PermissionsModel) {
        self.state = state
        self.permissions = permissions
    }

    func show(_ pane: SettingsPane? = nil) {
        if let pane { selection.pane = pane }
        if window == nil {
            let view = SettingsView(state: state, permissions: permissions, selection: selection, settings: state.settings)
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = tr("การตั้งค่า \(AppInfo.name)", "\(AppInfo.name) Settings")
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentMinSize = NSSize(width: 680, height: 460)
            w.setContentSize(NSSize(width: 780, height: 540))
            w.center()
            // Comes back at the size and place it was last left.
            w.setFrameAutosaveName("PIslandSettings")
            window = w
            languageObserver = state.settings.$language.dropFirst().sink { [weak w] _ in
                DispatchQueue.main.async { w?.title = tr("การตั้งค่า \(AppInfo.name)", "\(AppInfo.name) Settings") }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    let state: NotchState
    let permissions: PermissionsModel
    @ObservedObject var selection: SettingsSelection
    @ObservedObject var settings: AppSettings

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(AppInfo.name).font(.headline)
                        Text(tr("เวอร์ชัน \(AppInfo.version)", "Version \(AppInfo.version)")).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.top, 36)
                .padding(.bottom, 10)
                List(SettingsPane.allCases, selection: $selection.pane) { pane in
                    Label {
                        Text(pane.title)
                    } icon: {
                        Image(systemName: pane.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 6).fill(pane.color))
                    }
                    .tag(pane)
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationTitle(selection.pane?.title ?? "")
        }
        .frame(minWidth: 680, maxWidth: .infinity, minHeight: 460, maxHeight: .infinity)
        .environment(\.locale, Lang.locale)
        .id(settings.language) // rebuild every label when the language changes
    }

    @ViewBuilder private var detail: some View {
        switch selection.pane ?? .general {
        case .general: GeneralPane(settings: settings, state: state)
        case .alerts: AlertsPane(settings: settings, focus: state.focus)
        case .music: MusicPane(settings: settings)
        case .calendar: CalendarWeatherPane(settings: settings, calendar: state.calendar, weather: state.weather)
        case .clipboard: ClipboardPane(settings: settings, clipboard: state.clipboard)
        case .permissions: PermissionsPane(model: permissions, settings: settings)
        case .about: AboutPane(settings: settings, updates: state.updates)
        }
    }
}

/// A switch with a one-line explanation under its title.
private struct DescribedToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title)
            Text(detail)
        }
    }
}

// MARK: - Panes

private struct GeneralPane: View {
    @ObservedObject var settings: AppSettings
    let state: NotchState

    var body: some View {
        Form {
            Section {
                Picker(tr("ภาษา", "Language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text(tr("ภาษา", "Language"))
            } footer: {
                Text(tr("\"ตามเครื่อง\" ใช้ภาษาเดียวกับ macOS", "\"System\" follows the language macOS uses"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Picker(tr("ตอนเล่นเพลง", "While music plays"), selection: $settings.closedStyle) {
                    Text(tr("ปีกเล็ก", "Small wings")).tag("wings")
                    Text(tr("แถบยาว", "Slim bar")).tag("mini")
                }
                .pickerStyle(.segmented)
                Picker(tr("รูปแบบ", "Style"), selection: $settings.notchStyle) {
                    Text(tr("ดำ", "Black")).tag("black")
                    Text(tr("กระจก", "Glass")).tag("glass")
                }
                .pickerStyle(.segmented)
                if settings.notchStyle == "glass" {
                    LabeledContent(tr("ความเข้มของกระจก", "Glass darkness")) {
                        HStack {
                            Text(tr("ใส", "Clear")).font(.caption).foregroundStyle(.secondary)
                            Slider(value: $settings.glassTint, in: 0...0.7)
                            Text(tr("เข้ม", "Dark")).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(tr("หน้าตารอยบาก", "Notch look"))
            } footer: {
                Text(glassNote).font(.caption).foregroundStyle(.secondary)
            }
            Section(tr("ขนาดรอยบากตอนกางออก", "Open notch size")) {
                Picker(tr("ขนาด", "Size"), selection: $settings.sizeScale) {
                    ForEach(AppSettings.sizeOptions, id: \.scale) { Text($0.name).tag($0.scale) }
                }
                .pickerStyle(.segmented)
            }
            Section(tr("การทำงาน", "Behaviour")) {
                DescribedToggle(title: tr("เปิดตอนเข้าเครื่อง", "Launch at Login"), detail: tr("P Island เริ่มทำงานเองทุกครั้งที่เปิดเครื่อง", "P Island starts by itself whenever you log in"),
                                isOn: $settings.launchAtLogin)
                DescribedToggle(title: tr("สั่นที่แทร็กแพด", "Trackpad haptics"), detail: tr("สั่นเบา ๆ ตอนรอยบากกางออก", "A light tap when the notch opens"),
                                isOn: $settings.haptics)
                DescribedToggle(title: tr("ตรวจหาเวอร์ชันใหม่อัตโนมัติ", "Check for updates automatically"),
                                detail: tr("วันละครั้งจาก GitHub ถ้ามีเวอร์ชันใหม่ รอยบากจะบอก", "Once a day from GitHub; the notch tells you when a new version is out"),
                                isOn: $settings.checkUpdates)
            }
            Section(tr("ปุ่มลัด", "Shortcuts")) {
                LabeledContent(tr("เปิด/ปิดรอยบาก", "Open/close the notch"), value: "⌃⌥I")
                LabeledContent(tr("ไปที่ตัวจับเวลา", "Go to the timer"), value: "⌃⌥T")
            }
            Section {
                Button(tr("เล่นเดโมการ์ดแจ้งเตือน", "Play notch card demo")) { Demo.runAlerts(state: state) }
            }
        }
        .formStyle(.grouped)
    }

    private var glassNote: String {
        let bar = tr("แถบยาว: รอยบากยืดเป็นเครื่องเล่นเพลงบาง ๆ บนแถบเมนู กดเล่น/ข้ามเพลงได้ทันที (จะบังเมนูบางส่วนขณะเล่นเพลง) ",
                     "Slim bar: the notch stretches into a thin player across the menu bar, with play and skip right there (it covers part of the menu bar while music plays). ")
        let kind: String
        if #available(macOS 26.0, *) {
            kind = tr("ใช้ Liquid Glass ของ macOS", "uses macOS Liquid Glass")
        } else {
            kind = tr("เป็นกระจกฝ้าแบบเลียนแบบ (Liquid Glass ของจริงจะเปิดใช้เองเมื่ออัปเดตเป็น macOS 26)", "is a frosted-glass look-alike (real Liquid Glass turns on by itself on macOS 26)")
        }
        return bar + tr("กระจกแสดงตอนกางรอยบากและตอนการ์ดยืดลงมา \(kind) ตอนหดจะเป็นสีดำเสมอเพื่อกลืนกับรอยบากจริง", "Glass shows when the notch opens and when cards drop down; it \(kind). Closed, the notch stays black to blend with the real one.")
    }
}

private struct AlertsPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var focus: FocusMonitor

    var body: some View {
        Form {
            Section(tr("แสดงที่รอยบาก", "Show in the notch")) {
                DescribedToggle(title: tr("แจ้งเตือนจากแอปอื่น", "Other apps' notifications"), detail: tr("LINE, Messages, Mail และทุกแอปที่มีแจ้งเตือน", "LINE, Messages, Mail and any app that sends notifications"),
                                isOn: $settings.appNotifications)
                DescribedToggle(title: tr("ชื่อเพลงตอนเปลี่ยนเพลง", "Song changes"), detail: tr("รอยบากยืดลงมาโชว์ปกและชื่อเพลงใหม่", "The notch drops down with the new song's cover and title"),
                                isOn: $settings.songPeek)
                DescribedToggle(title: tr("ระดับเสียงและความสว่าง", "Volume & brightness"), detail: tr("แถบปรับที่รอยบากตอนกดปุ่มบนคีย์บอร์ด", "A slider in the notch when you press the keyboard keys"),
                                isOn: $settings.volumeHUD)
                DescribedToggle(title: tr("แจ้งเตือนแบตเตอรี่", "Battery alerts"), detail: tr("แบตเหลือ 20%, 10%, 5% ชาร์จเต็ม และเสียบ/ถอดสาย", "20%, 10%, 5% left, fully charged, and plugging in or out"),
                                isOn: $settings.batteryAlerts)
                DescribedToggle(title: tr("อุปกรณ์บลูทูธ", "Bluetooth devices"), detail: tr("AirPods และอุปกรณ์อื่นเชื่อมต่อหรือตัดการเชื่อมต่อ", "AirPods and other devices connecting or disconnecting"),
                                isOn: $settings.bluetoothAlerts)
                DescribedToggle(title: tr("การประชุม", "Meetings"), detail: tr("ปุ่มเข้าร่วม Zoom, Meet, Teams ก่อนเริ่มประมาณ 1 นาที", "A Join button for Zoom, Meet or Teams about a minute before"),
                                isOn: $settings.meetingAlerts)
            }
            Section {
                DescribedToggle(title: tr("ดาวน์โหลด", "Downloads"),
                                detail: tr("ความคืบหน้าบนรอยบากตอนโหลดไฟล์จาก Safari, Chrome หรือ Firefox และบอกเมื่อเสร็จ", "Progress on the notch while Safari, Chrome or Firefox downloads, and a card when it's done"),
                                isOn: $settings.liveDownloads)
                DescribedToggle(title: tr("กล้องและไมค์", "Camera & microphone"),
                                detail: tr("บอกเมื่อมีแอปเริ่มหรือเลิกใช้กล้องหรือไมค์", "Shows when an app starts or stops using the camera or microphone"),
                                isOn: $settings.liveCameraMic)
                DescribedToggle(title: tr("นับถอยหลังก่อนนัด", "Countdown to the next event"),
                                detail: tr("10 นาทีก่อนนัดหรือประชุม รอยบากนับถอยหลังให้", "The notch counts down the last 10 minutes before an event or meeting"),
                                isOn: $settings.liveMeetingCountdown)
                DescribedToggle(title: "Caps Lock",
                                detail: tr("บอกตอนเปิดหรือปิด Caps Lock", "Shows Caps Lock turning on or off"),
                                isOn: $settings.liveCapsLock)
            } header: {
                Text("Live Activity")
            }
            Section(tr("โหมด Focus", "Focus")) {
                DescribedToggle(title: tr("เงียบเมื่อเปิดโหมด Focus", "Stay quiet during Focus"),
                                detail: tr("พักแจ้งเตือนจากแอปอื่น ชื่อเพลง และบลูทูธ แต่ยังเตือนแบตใกล้หมด ตัวจับเวลา และประชุม", "Holds back app notifications, song changes and Bluetooth; low battery, timers and meetings still show"),
                                isOn: $settings.respectFocus)
                LabeledContent(tr("ตอนนี้", "Now"), value: focus.isActive
                    ? tr("เปิดโหมด \(focus.modeName ?? "Focus") อยู่", "\(focus.modeName ?? "Focus") is on")
                    : tr("ไม่ได้เปิด", "Off"))
            }
        }
        .formStyle(.grouped)
    }
}

private struct MusicPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section(tr("ตอนเล่นเพลง", "While music plays")) {
                DescribedToggle(title: tr("แสงแอมเบียนต์จากปกเพลง", "Ambient light from the cover"),
                                detail: tr("แผงสีดำมีแสงฟุ้งสีเดียวกับปกเพลงลอยอยู่ด้านหลัง", "A soft glow in the cover's colours drifts behind the black panel"),
                                isOn: $settings.ambientGlow)
                DescribedToggle(title: tr("พลิกปกเพลงตอนเปลี่ยนเพลง", "Flip the cover on song change"), detail: tr("ปกหมุนเปลี่ยนเป็นปกใหม่ครั้งเดียวต่อเพลง", "The cover turns over to the new one, once per song"),
                                isOn: $settings.artworkFlip)
                DescribedToggle(title: tr("เนื้อเพลง", "Lyrics"),
                                detail: tr("เนื้อเพลงที่วิ่งตามเพลงข้างตัวเล่นเพลง จาก LRCLIB (ส่งแค่ชื่อเพลง ศิลปิน และความยาวเพลง)", "Lyrics that follow the song beside the player, from LRCLIB (only the title, artist and length are sent)"),
                                isOn: $settings.lyrics)
                DescribedToggle(title: tr("เนื้อเพลงบนแถบเพลงแบบแคบ", "Lyrics in the slim bar"),
                                detail: tr("ท่อนที่กำลังร้องแทนชื่อเพลง", "The line being sung instead of the song name"),
                                isOn: $settings.lyricsInSlimBar)
                    .disabled(!settings.lyrics)
                DescribedToggle(title: tr("คลื่นเสียงตามเพลงจริง", "Live waveform"),
                                detail: tr("แท่งบนรอยบากขยับตามเสียงที่เครื่องเล่น (ขอสิทธิ์ System Audio Recording)", "The bars follow what your Mac is playing (asks for System Audio Recording)"),
                                isOn: $settings.liveWaveform)
            }
            Section(tr("แอปเพลงที่รองรับ", "Supported music apps")) {
                LabeledContent("Apple Music", value: tr("ใช้ได้ทันที", "Works right away"))
                LabeledContent("Spotify", value: tr("ใช้ได้ทันที", "Works right away"))
                LabeledContent("YouTube Music (Chrome)", value: tr("ผ่านส่วนขยาย P Island for YouTube Music", "Through the P Island for YouTube Music extension"))
            }
        }
        .formStyle(.grouped)
    }
}

private struct CalendarWeatherPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var calendar: CalendarManager
    @ObservedObject var weather: WeatherManager

    var body: some View {
        Form {
            Section(tr("ปฏิทิน", "Calendar")) {
                LabeledContent(tr("การเข้าถึงปฏิทิน", "Calendar access")) {
                    switch calendar.status {
                    case .authorized: Text(tr("อนุญาตแล้ว", "Allowed")).foregroundStyle(.green)
                    case .notDetermined: Button(tr("อนุญาต", "Allow")) { calendar.requestAccess() }
                    case .denied: Button(tr("เปิดการตั้งค่า", "Open Settings")) { calendar.openPrivacySettings() }
                    }
                }
                DescribedToggle(title: tr("เตือนก่อนประชุม", "Meeting reminders"), detail: tr("นัดที่มีลิงก์ Zoom, Meet, Teams, FaceTime หรือ Webex", "Events with a Zoom, Meet, Teams, FaceTime or Webex link"),
                                isOn: $settings.meetingAlerts)
            }
            Section {
                LabeledContent(tr("เมือง", "City")) {
                    HStack {
                        Text(weather.city)
                        Button(tr("เปลี่ยน…", "Change…")) { weather.chooseCity() }
                    }
                }
                if let temp = weather.temperature, let code = weather.code {
                    LabeledContent(tr("ตอนนี้", "Now"), value: "\(Int(temp.rounded()))° · \(WeatherManager.describe(code))")
                }
            } header: {
                Text(tr("สภาพอากาศ", "Weather"))
            } footer: {
                Text(tr("ข้อมูลสภาพอากาศจาก Open-Meteo.com", "Weather data from Open-Meteo.com")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ClipboardPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var clipboard: ClipboardManager

    var body: some View {
        Form {
            Section {
                DescribedToggle(title: tr("เก็บประวัติคลิปบอร์ด", "Keep clipboard history"), detail: tr("จำ \(ClipboardManager.limit) รายการล่าสุดที่คัดลอก", "Remembers the last \(ClipboardManager.limit) things you copied"),
                                isOn: $settings.clipboardHistory)
                LabeledContent(tr("ตอนนี้มี", "Items now"), value: tr("\(clipboard.items.count) รายการ", "\(clipboard.items.count)"))
                Button(tr("ล้างประวัติทั้งหมด", "Clear All History"), role: .destructive) { clipboard.clear() }
                    .disabled(clipboard.items.isEmpty)
            } footer: {
                Text(tr("เก็บไว้ในหน่วยความจำเท่านั้น หายเมื่อปิดแอป และไม่เก็บรหัสผ่านจากแอปจัดการรหัสผ่าน", "Kept in memory only, gone when the app quits, and never stores passwords from password managers"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PermissionsPane: View {
    let model: PermissionsModel
    @ObservedObject var settings: AppSettings

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(tr("กดปุ่มด้านขวาของแต่ละรายการเพื่อเปิดสิทธิ์ สถานะจะอัปเดตเองทันที", "Use the button on the right of each row to grant it. The status updates by itself."))
                    .font(.callout).foregroundStyle(.secondary)
                PermissionsList(model: model, settings: settings)
                Toggle(tr("เปิดหน้านี้ตอนเปิดแอป ถ้ายังขาดสิทธิ์สำคัญ", "Open this page at launch if something important is missing"), isOn: $settings.showPermissionsAtLaunch)
                    .font(.callout)
            }
            .padding(20)
        }
    }
}

private struct AboutPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var updates: UpdateChecker

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 10)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
            Text(AppInfo.name)
                .font(.system(size: 30, weight: .bold))
            Text(tr("เวอร์ชัน \(AppInfo.version) (\(AppInfo.build))", "Version \(AppInfo.version) (\(AppInfo.build))"))
                .foregroundStyle(.secondary)
            Text(tr("รอยบากอัจฉริยะสำหรับ MacBook\nเพลง แจ้งเตือน ไฟล์ ปฏิทิน และอีกมากมายในที่เดียว", "A smart notch for your MacBook\nMusic, notifications, files, calendar and more in one place"))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            updateRow

            Divider().frame(width: 240).padding(.vertical, 6)

            VStack(spacing: 4) {
                Text(tr("พัฒนาโดย", "Developed by")).font(.caption).foregroundStyle(.secondary)
                Text(AppInfo.developer).font(.title2.weight(.semibold))
            }

            Spacer()

            VStack(spacing: 3) {
                Text(tr("ผู้ช่วยเขียนโค้ด: Claude (Anthropic)", "Coding assistant: Claude (Anthropic)"))
                Text(tr("ข้อมูลสภาพอากาศ: Open-Meteo.com (CC BY 4.0)", "Weather data: Open-Meteo.com (CC BY 4.0)"))
                Text(tr("เนื้อเพลง: LRCLIB.net", "Lyrics: LRCLIB.net"))
                Text(tr("สร้างด้วย Swift และ SwiftUI", "Built with Swift and SwiftUI"))
                Text("© 2026 \(AppInfo.developer)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
    }
    @ViewBuilder private var updateRow: some View {
        HStack(spacing: 8) {
            switch updates.status {
            case .checking:
                ProgressView().controlSize(.small)
                Text(tr("กำลังตรวจ…", "Checking…")).foregroundStyle(.secondary)
            case .upToDate:
                Label(tr("เป็นเวอร์ชันล่าสุดแล้ว", "You're up to date"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .available(let release):
                Label(tr("มีเวอร์ชัน \(release.version) แล้ว", "Version \(release.version) is out"), systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                Button(tr("ดาวน์โหลด", "Download")) { NSWorkspace.shared.open(release.page) }
            case .failed:
                Text(tr("ตรวจไม่สำเร็จ ลองใหม่อีกครั้ง", "Couldn't check. Try again.")).foregroundStyle(.secondary)
                Button(tr("ตรวจหาอัปเดต", "Check for Updates")) { updates.check() }
            case .idle:
                Button(tr("ตรวจหาอัปเดต", "Check for Updates")) { updates.check() }
            }
        }
        .font(.callout)
        .frame(height: 24)
    }

}
