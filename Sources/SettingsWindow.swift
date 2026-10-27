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
        case .general: return "ทั่วไป"
        case .alerts: return "การแจ้งเตือน"
        case .music: return "เพลง"
        case .calendar: return "ปฏิทินและอากาศ"
        case .clipboard: return "คลิปบอร์ด"
        case .permissions: return "สิทธิ์การเข้าถึง"
        case .about: return "เกี่ยวกับ"
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

    init(state: NotchState, permissions: PermissionsModel) {
        self.state = state
        self.permissions = permissions
    }

    func show(_ pane: SettingsPane? = nil) {
        if let pane { selection.pane = pane }
        if window == nil {
            let view = SettingsView(state: state, permissions: permissions, selection: selection, settings: state.settings)
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "การตั้งค่า \(AppInfo.name)"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentMinSize = NSSize(width: 680, height: 460)
            w.setContentSize(NSSize(width: 780, height: 540))
            w.center()
            // Comes back at the size and place it was last left.
            w.setFrameAutosaveName("PIslandSettings")
            window = w
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
                        Text("เวอร์ชัน \(AppInfo.version)").font(.caption).foregroundStyle(.secondary)
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
        .environment(\.locale, .thai)
    }

    @ViewBuilder private var detail: some View {
        switch selection.pane ?? .general {
        case .general: GeneralPane(settings: settings, state: state)
        case .alerts: AlertsPane(settings: settings, focus: state.focus)
        case .music: MusicPane(settings: settings)
        case .calendar: CalendarWeatherPane(settings: settings, calendar: state.calendar, weather: state.weather)
        case .clipboard: ClipboardPane(settings: settings, clipboard: state.clipboard)
        case .permissions: PermissionsPane(model: permissions, settings: settings)
        case .about: AboutPane()
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
                Picker("รูปแบบ", selection: $settings.notchStyle) {
                    Text("ดำ").tag("black")
                    Text("กระจก").tag("glass")
                }
                .pickerStyle(.segmented)
                if settings.notchStyle == "glass" {
                    LabeledContent("ความเข้มของกระจก") {
                        HStack {
                            Text("ใส").font(.caption).foregroundStyle(.secondary)
                            Slider(value: $settings.glassTint, in: 0...0.7)
                            Text("เข้ม").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("หน้าตารอยบาก")
            } footer: {
                Text(glassNote).font(.caption).foregroundStyle(.secondary)
            }
            Section("ขนาดรอยบากตอนกางออก") {
                Picker("ขนาด", selection: $settings.sizeScale) {
                    ForEach(AppSettings.sizeOptions, id: \.scale) { Text($0.name).tag($0.scale) }
                }
                .pickerStyle(.segmented)
            }
            Section("การทำงาน") {
                DescribedToggle(title: "เปิดตอนเข้าเครื่อง", detail: "P Island เริ่มทำงานเองทุกครั้งที่เปิดเครื่อง",
                                isOn: $settings.launchAtLogin)
                DescribedToggle(title: "สั่นที่แทร็กแพด", detail: "สั่นเบา ๆ ตอนรอยบากกางออก",
                                isOn: $settings.haptics)
            }
            Section("ปุ่มลัด") {
                LabeledContent("เปิด/ปิดรอยบาก", value: "⌃⌥I")
                LabeledContent("ไปที่ตัวจับเวลา", value: "⌃⌥T")
            }
            Section {
                Button("เล่นเดโมการ์ดแจ้งเตือน") { Demo.runAlerts(state: state) }
            }
        }
        .formStyle(.grouped)
    }

    private var glassNote: String {
        let kind: String
        if #available(macOS 26.0, *) {
            kind = "ใช้ Liquid Glass ของ macOS"
        } else {
            kind = "เป็นกระจกฝ้าแบบเลียนแบบ (Liquid Glass ของจริงจะเปิดใช้เองเมื่ออัปเดตเป็น macOS 26)"
        }
        return "กระจกแสดงตอนกางรอยบากและตอนการ์ดยืดลงมา \(kind) ตอนหดจะเป็นสีดำเสมอเพื่อกลืนกับรอยบากจริง"
    }
}

private struct AlertsPane: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var focus: FocusMonitor

    var body: some View {
        Form {
            Section("แสดงที่รอยบาก") {
                DescribedToggle(title: "แจ้งเตือนจากแอปอื่น", detail: "LINE, Messages, Mail และทุกแอปที่มีแจ้งเตือน",
                                isOn: $settings.appNotifications)
                DescribedToggle(title: "ชื่อเพลงตอนเปลี่ยนเพลง", detail: "รอยบากยืดลงมาโชว์ปกและชื่อเพลงใหม่",
                                isOn: $settings.songPeek)
                DescribedToggle(title: "ระดับเสียงและความสว่าง", detail: "แถบปรับที่รอยบากตอนกดปุ่มบนคีย์บอร์ด",
                                isOn: $settings.volumeHUD)
                DescribedToggle(title: "แจ้งเตือนแบตเตอรี่", detail: "แบตเหลือ 20%, 10%, 5% ชาร์จเต็ม และเสียบ/ถอดสาย",
                                isOn: $settings.batteryAlerts)
                DescribedToggle(title: "อุปกรณ์บลูทูธ", detail: "AirPods และอุปกรณ์อื่นเชื่อมต่อหรือตัดการเชื่อมต่อ",
                                isOn: $settings.bluetoothAlerts)
                DescribedToggle(title: "การประชุม", detail: "ปุ่มเข้าร่วม Zoom, Meet, Teams ก่อนเริ่มประมาณ 1 นาที",
                                isOn: $settings.meetingAlerts)
            }
            Section("โหมด Focus") {
                DescribedToggle(title: "เงียบเมื่อเปิดโหมด Focus",
                                detail: "พักแจ้งเตือนจากแอปอื่น ชื่อเพลง และบลูทูธ แต่ยังเตือนแบตใกล้หมด ตัวจับเวลา และประชุม",
                                isOn: $settings.respectFocus)
                LabeledContent("ตอนนี้", value: focus.isActive ? "เปิดโหมด \(focus.modeName ?? "Focus") อยู่" : "ไม่ได้เปิด")
            }
        }
        .formStyle(.grouped)
    }
}

private struct MusicPane: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("ตอนเล่นเพลง") {
                DescribedToggle(title: "พลิกปกเพลงตอนเปลี่ยนเพลง", detail: "ปกหมุนเปลี่ยนเป็นปกใหม่ครั้งเดียวต่อเพลง",
                                isOn: $settings.artworkFlip)
                DescribedToggle(title: "คลื่นเสียงตามเพลงจริง",
                                detail: "แท่งบนรอยบากขยับตามเสียงที่เครื่องเล่น (ขอสิทธิ์ System Audio Recording)",
                                isOn: $settings.liveWaveform)
            }
            Section("แอปเพลงที่รองรับ") {
                LabeledContent("Apple Music", value: "ใช้ได้ทันที")
                LabeledContent("Spotify", value: "ใช้ได้ทันที")
                LabeledContent("YouTube Music (Chrome)", value: "ผ่านส่วนขยาย P Island for YouTube Music")
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
            Section("ปฏิทิน") {
                LabeledContent("การเข้าถึงปฏิทิน") {
                    switch calendar.status {
                    case .authorized: Text("อนุญาตแล้ว").foregroundStyle(.green)
                    case .notDetermined: Button("อนุญาต") { calendar.requestAccess() }
                    case .denied: Button("เปิดการตั้งค่า") { calendar.openPrivacySettings() }
                    }
                }
                DescribedToggle(title: "เตือนก่อนประชุม", detail: "นัดที่มีลิงก์ Zoom, Meet, Teams, FaceTime หรือ Webex",
                                isOn: $settings.meetingAlerts)
            }
            Section {
                LabeledContent("เมือง") {
                    HStack {
                        Text(weather.city)
                        Button("เปลี่ยน…") { weather.chooseCity() }
                    }
                }
                if let temp = weather.temperature, let code = weather.code {
                    LabeledContent("ตอนนี้", value: "\(Int(temp.rounded()))° · \(WeatherManager.describe(code))")
                }
            } header: {
                Text("สภาพอากาศ")
            } footer: {
                Text("ข้อมูลสภาพอากาศจาก Open-Meteo.com").font(.caption).foregroundStyle(.secondary)
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
                DescribedToggle(title: "เก็บประวัติคลิปบอร์ด", detail: "จำ \(ClipboardManager.limit) รายการล่าสุดที่คัดลอก",
                                isOn: $settings.clipboardHistory)
                LabeledContent("ตอนนี้มี", value: "\(clipboard.items.count) รายการ")
                Button("ล้างประวัติทั้งหมด", role: .destructive) { clipboard.clear() }
                    .disabled(clipboard.items.isEmpty)
            } footer: {
                Text("เก็บไว้ในหน่วยความจำเท่านั้น หายเมื่อปิดแอป และไม่เก็บรหัสผ่านจากแอปจัดการรหัสผ่าน")
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
                Text("กดปุ่มด้านขวาของแต่ละรายการเพื่อเปิดสิทธิ์ สถานะจะอัปเดตเองทันที")
                    .font(.callout).foregroundStyle(.secondary)
                PermissionsList(model: model, settings: settings)
                Toggle("เปิดหน้านี้ตอนเปิดแอป ถ้ายังขาดสิทธิ์สำคัญ", isOn: $settings.showPermissionsAtLaunch)
                    .font(.callout)
            }
            .padding(20)
        }
    }
}

private struct AboutPane: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 10)
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
            Text(AppInfo.name)
                .font(.system(size: 30, weight: .bold))
            Text("เวอร์ชัน \(AppInfo.version) (\(AppInfo.build))")
                .foregroundStyle(.secondary)
            Text("รอยบากอัจฉริยะสำหรับ MacBook\nเพลง แจ้งเตือน ไฟล์ ปฏิทิน และอีกมากมายในที่เดียว")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Divider().frame(width: 240).padding(.vertical, 6)

            VStack(spacing: 4) {
                Text("พัฒนาโดย").font(.caption).foregroundStyle(.secondary)
                Text(AppInfo.developer).font(.title2.weight(.semibold))
            }

            Spacer()

            VStack(spacing: 3) {
                Text("ผู้ช่วยเขียนโค้ด: Claude (Anthropic)")
                Text("ข้อมูลสภาพอากาศ: Open-Meteo.com (CC BY 4.0)")
                Text("สร้างด้วย Swift และ SwiftUI")
                Text("© 2026 \(AppInfo.developer)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
    }
}
