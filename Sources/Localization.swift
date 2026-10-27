import Foundation

/// The language P Island speaks. "system" follows the Mac's preferred language.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, thai = "th", english = "en"

    var id: String { rawValue }

    /// Shown in both languages so it can be found whatever the current one is.
    var label: String {
        switch self {
        case .system: return tr("ตามเครื่อง (System)", "System (ตามเครื่อง)")
        case .thai: return "ไทย"
        case .english: return "English"
        }
    }
}

enum Lang {
    /// Set from AppSettings at launch and whenever the user changes it.
    static var setting: AppLanguage = .system

    static var isThai: Bool {
        switch setting {
        case .thai: return true
        case .english: return false
        case .system: return Locale.preferredLanguages.first?.hasPrefix("th") ?? false
        }
    }

    /// Two-letter code for web services (weather place names).
    static var code: String { isThai ? "th" : "en" }

    /// Dates, weekdays and times follow the app language; Thai uses the Buddhist year.
    static var locale: Locale {
        if isThai { return Locale(identifier: "th_TH") }
        return setting == .english ? Locale(identifier: "en_US") : Locale.current
    }
}

/// Picks the Thai or English text for the current app language.
func tr(_ thai: String, _ english: String) -> String {
    Lang.isThai ? thai : english
}
