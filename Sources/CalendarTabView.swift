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
        let cal = Calendar.current
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

struct DayEvents: View {
    @ObservedObject var calendar: CalendarManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(calendar.selectedDay, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.red)
            switch calendar.status {
            case .notDetermined:
                Text("See your events here").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                Button("Allow Calendar") { calendar.requestAccess() }.buttonStyle(PillButtonStyle())
            case .denied:
                Text("No calendar access").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                Button("Open Settings") { calendar.openPrivacySettings() }.buttonStyle(PillButtonStyle())
            case .authorized:
                if calendar.selectedEvents.isEmpty {
                    Text("No events").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(calendar.selectedEvents) { EventRow(event: $0) }
                        }
                    }
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
            .help("Change city")

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
                    Text("H \(Int(today.high.rounded()))°  L \(Int(today.low.rounded()))°")
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
                Text(weather.failed ? "Weather unavailable" : "Loading…")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                if weather.failed {
                    Button("Retry") { weather.refresh() }.buttonStyle(PillButtonStyle())
                }
            }
            Spacer(minLength: 0)
        }
    }
}
