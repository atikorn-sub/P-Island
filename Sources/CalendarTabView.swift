import SwiftUI

struct CalendarTabView: View {
    @ObservedObject var calendar: CalendarManager
    @ObservedObject var weather: WeatherManager

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MonthGrid(calendar: calendar)
                .frame(width: 200)
            divider
            DayEvents(calendar: calendar)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            divider
            WeatherCard(weather: weather)
                .frame(width: 140)
        }
        .onAppear { calendar.reload() }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
    }
}

struct MonthGrid: View {
    @ObservedObject var calendar: CalendarManager

    var body: some View {
        let cal = Calendar.current
        let columns = Array(repeating: GridItem(.fixed(26), spacing: 2), count: 7)
        VStack(spacing: 4) {
            HStack {
                Text(calendar.month, format: .dateTime.month(.wide).year())
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button { calendar.showMonth(offset: -1) } label: { Image(systemName: "chevron.left") }
                Button { calendar.showMonth(offset: 1) } label: { Image(systemName: "chevron.right") }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))

            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
                ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 20) }
                ForEach(1...daysInMonth, id: \.self) { day in
                    let date = cal.date(byAdding: .day, value: day - 1, to: calendar.month)!
                    DayCell(day: day,
                            isToday: cal.isDateInToday(date),
                            isSelected: cal.isDate(date, inSameDayAs: calendar.selectedDay),
                            isBusy: calendar.busyDays.contains(day))
                        .onTapGesture { calendar.selectedDay = date }
                }
            }
        }
    }

    private var weekdaySymbols: [String] {
        var cal = Calendar.current
        cal.locale = Lang.locale
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var leadingBlanks: Int {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: calendar.month)
        return (weekday - cal.firstWeekday + 7) % 7
    }

    private var daysInMonth: Int {
        Calendar.current.range(of: .day, in: .month, for: calendar.month)?.count ?? 30
    }
}

struct DayCell: View {
    let day: Int
    let isToday: Bool
    let isSelected: Bool
    let isBusy: Bool

    var body: some View {
        VStack(spacing: 1) {
            Text("\(day)")
                .font(.system(size: 10, weight: isToday ? .bold : .regular).monospacedDigit())
                .frame(width: 18, height: 16)
                .background(Circle().fill(isToday ? Color.red : isSelected ? Color.white.opacity(0.2) : .clear))
            Circle()
                .fill(isBusy ? Color.white.opacity(0.6) : .clear)
                .frame(width: 3, height: 3)
        }
        .frame(height: 20)
        .contentShape(Rectangle())
    }
}

/// The selected day: step through days with the arrows, and switch between its events and reminders.
struct DayEvents: View {
    @ObservedObject var calendar: CalendarManager
    @AppStorage("dayListMode") private var mode = "events"

    var body: some View {
        let isToday = Calendar.current.isDateInToday(calendar.selectedDay)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button { calendar.step(days: -1) } label: { Image(systemName: "chevron.left") }
                Text(calendar.selectedDay, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isToday ? .red : .white)
                    .lineLimit(1)
                Button { calendar.step(days: 1) } label: { Image(systemName: "chevron.right") }
                Spacer(minLength: 0)
                if !isToday {
                    Button(tr("วันนี้", "Today")) { calendar.goToToday() }
                        .buttonStyle(PillButtonStyle())
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))

            HStack(spacing: 4) {
                modeButton("events", tr("นัดหมาย", "Events"), count: calendar.selectedEvents.count)
                modeButton("reminders", tr("เตือนความจำ", "Reminders"), count: calendar.reminders.count)
            }

            Group {
                if mode == "reminders" { reminders } else { events }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .animation(.easeInOut(duration: 0.2), value: calendar.selectedDay)
    }

    @ViewBuilder private var events: some View {
        switch calendar.status {
        case .notDetermined:
            note(tr("ดูนัดหมายของคุณที่นี่", "See your events here"))
            Button(tr("อนุญาตปฏิทิน", "Allow Calendar")) { calendar.requestAccess() }.buttonStyle(PillButtonStyle())
        case .denied:
            note(tr("ยังไม่ได้อนุญาตปฏิทิน", "No calendar access"))
            Button(tr("เปิดการตั้งค่า", "Open Settings")) { calendar.openPrivacySettings() }.buttonStyle(PillButtonStyle())
        case .authorized:
            if calendar.selectedEvents.isEmpty {
                note(tr("ไม่มีนัดหมาย", "No events"))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(calendar.selectedEvents) { EventRow(event: $0) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var reminders: some View {
        switch calendar.remindersStatus {
        case .notDetermined:
            note(tr("ดูและติ๊กรายการเตือนความจำได้ที่นี่", "See and tick off your reminders here"))
            Button(tr("อนุญาต Reminders", "Allow Reminders")) { calendar.requestRemindersAccess() }.buttonStyle(PillButtonStyle())
        case .denied:
            note(tr("ยังไม่ได้อนุญาต Reminders", "No Reminders access"))
            Button(tr("เปิดการตั้งค่า", "Open Settings")) { calendar.openRemindersPrivacySettings() }.buttonStyle(PillButtonStyle())
        case .authorized:
            if calendar.reminders.isEmpty {
                note(tr("ไม่มีรายการค้าง 🎉", "Nothing to do 🎉"))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(calendar.reminders) { item in
                            ReminderRow(item: item) { calendar.complete(item) }
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: calendar.reminders)
                }
            }
        }
    }

    private func modeButton(_ id: String, _ title: String, count: Int) -> some View {
        let selected = mode == id
        return Button { mode = id } label: {
            HStack(spacing: 4) {
                Text(title)
                if count > 0 {
                    Text("\(count)").foregroundStyle(.white.opacity(0.5))
                }
            }
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white.opacity(selected ? 0.95 : 0.45))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(selected ? 0.14 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
    }
}

/// A reminder with a circle to tick it off; the circle fills before the row slides away.
struct ReminderRow: View {
    let item: ReminderItem
    let onDone: () -> Void
    @State private var ticked = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) { ticked = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onDone() }
            } label: {
                ZStack {
                    Circle().strokeBorder(Color(nsColor: item.color), lineWidth: 1.5)
                    if ticked {
                        Circle().fill(Color(nsColor: item.color)).padding(3)
                    }
                }
                .frame(width: 15, height: 15)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(tr("ทำเสร็จแล้ว", "Mark as done"))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .strikethrough(ticked)
                    .opacity(ticked ? 0.5 : 1)
                if let due = item.due {
                    Group {
                        if item.hasTime {
                            Text(due, format: Calendar.current.isDateInToday(due) ? .dateTime.hour().minute() : .dateTime.day().month(.abbreviated).hour().minute())
                        } else {
                            Text(due, format: .dateTime.day().month(.abbreviated))
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(item.overdue ? Color.red : Color.white.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct WeatherCard: View {
    @ObservedObject var weather: WeatherManager

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { weather.chooseCity() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "location.fill").font(.system(size: 8))
                    Text(weather.city).lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help(tr("เปลี่ยนเมือง", "Change city"))

            if let temp = weather.temperature, let code = weather.code {
                HStack(spacing: 6) {
                    Image(systemName: WeatherManager.symbol(for: code))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 24))
                    Text("\(Int(temp.rounded()))°")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                }
                Text(WeatherManager.describe(code))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                if let today = weather.days.first {
                    Text(tr("สูงสุด \(Int(today.high.rounded()))°  ต่ำสุด \(Int(today.low.rounded()))°", "H \(Int(today.high.rounded()))°  L \(Int(today.low.rounded()))°"))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
                HStack(spacing: 8) {
                    ForEach(weather.days.dropFirst().prefix(3)) { day in
                        VStack(spacing: 2) {
                            Text(day.date, format: .dateTime.weekday(.abbreviated))
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.5))
                            Image(systemName: WeatherManager.symbol(for: day.code))
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 12))
                            Text("\(Int(day.high.rounded()))°")
                                .font(.system(size: 10).monospacedDigit())
                        }
                    }
                }
                .padding(.top, 2)
            } else {
                Text(weather.failed ? tr("โหลดสภาพอากาศไม่ได้", "Weather unavailable") : tr("กำลังโหลด…", "Loading…"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                if weather.failed {
                    Button(tr("ลองใหม่", "Retry")) { weather.refresh() }.buttonStyle(PillButtonStyle())
                }
            }
            Spacer(minLength: 0)
        }
    }
}
