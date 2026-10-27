import AppKit

struct WeatherDay: Identifiable {
    let date: Date
    let code: Int
    let high: Double
    let low: Double
    var id: Date { date }
}

/// Weather from Open-Meteo (free, no API key) for a city the user picks; no location permission needed.
final class WeatherManager: ObservableObject {
    @Published private(set) var city: String
    @Published private(set) var temperature: Double?
    @Published private(set) var code: Int?
    @Published private(set) var days: [WeatherDay] = []
    @Published private(set) var failed = false

    private var latitude: Double
    private var longitude: Double
    private var timer: Timer?
    private let defaults = UserDefaults.standard

    init() {
        defaults.register(defaults: ["weather.city": "Bangkok", "weather.lat": 13.7563, "weather.lon": 100.5018])
        city = defaults.string(forKey: "weather.city") ?? "Bangkok"
        latitude = defaults.double(forKey: "weather.lat")
        longitude = defaults.double(forKey: "weather.lon")
        refresh()
        let t = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func refresh() {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "4"),
        ]
        URLSession.shared.dataTask(with: c.url!) { [weak self] data, _, _ in
            let forecast = data.flatMap { try? JSONDecoder().decode(Forecast.self, from: $0) }
            DispatchQueue.main.async { self?.apply(forecast) }
        }.resume()
    }

    /// Asks for a city name and looks it up with Open-Meteo's geocoder.
    func chooseCity() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "เมืองสำหรับสภาพอากาศ"
        alert.informativeText = "พิมพ์ชื่อเมือง เช่น กรุงเทพ, เชียงใหม่ หรือ Tokyo"
        let field = NSTextField(string: city)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "บันทึก")
        alert.addButton(withTitle: "ยกเลิก")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: name), .init(name: "count", value: "1"), .init(name: "language", value: "th")]
        URLSession.shared.dataTask(with: c.url!) { [weak self] data, _, _ in
            let place = data.flatMap { try? JSONDecoder().decode(Places.self, from: $0) }?.results?.first
            DispatchQueue.main.async {
                guard let self else { return }
                guard let place else {
                    let notFound = NSAlert()
                    notFound.messageText = "ไม่พบเมือง “\(name)”"
                    notFound.runModal()
                    return
                }
                self.city = place.name
                self.latitude = place.latitude
                self.longitude = place.longitude
                self.defaults.set(place.name, forKey: "weather.city")
                self.defaults.set(place.latitude, forKey: "weather.lat")
                self.defaults.set(place.longitude, forKey: "weather.lon")
                self.refresh()
            }
        }.resume()
    }

    private func apply(_ forecast: Forecast?) {
        guard let forecast else {
            failed = temperature == nil
            return
        }
        failed = false
        temperature = forecast.current.temperature_2m
        code = forecast.current.weather_code
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        let d = forecast.daily
        days = d.time.indices.compactMap { i in
            guard let date = parser.date(from: d.time[i]) else { return nil }
            return WeatherDay(date: date, code: d.weather_code[i], high: d.temperature_2m_max[i], low: d.temperature_2m_min[i])
        }
    }

    // MARK: WMO weather codes

    static func symbol(for code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61, 63, 66: return "cloud.rain.fill"
        case 65, 67: return "cloud.heavyrain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 80...82: return "cloud.sun.rain.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func describe(_ code: Int) -> String {
        switch code {
        case 0: return "ท้องฟ้าแจ่มใส"
        case 1, 2: return "มีเมฆบางส่วน"
        case 3: return "เมฆมาก"
        case 45, 48: return "หมอก"
        case 51...57: return "ฝนปรอย"
        case 61, 63, 66: return "ฝนตก"
        case 65, 67: return "ฝนตกหนัก"
        case 71...77, 85, 86: return "หิมะตก"
        case 80...82: return "ฝนตกเป็นช่วง ๆ"
        case 95...99: return "พายุฝนฟ้าคะนอง"
        default: return "มีเมฆ"
        }
    }

    // MARK: Open-Meteo JSON

    private struct Forecast: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
        }
        struct Daily: Decodable {
            let time: [String]
            let weather_code: [Int]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        let current: Current
        let daily: Daily
    }

    private struct Places: Decodable {
        struct Place: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
        }
        let results: [Place]?
    }
}
