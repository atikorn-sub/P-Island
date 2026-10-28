import Foundation

/// Looks for a newer P Island in the GitHub repo's download/latest.json, at launch and once a day.
/// Only reads that one public file; nothing about this Mac is sent.
final class UpdateChecker: ObservableObject {
    struct Release: Decodable, Equatable {
        let version: String
        /// Where to send people: the README's install section.
        let page: URL
    }

    enum Status: Equatable {
        case idle, checking, upToDate, available(Release), failed
    }

    @Published private(set) var status: Status = .idle

    /// Called on the main queue when an automatic check finds a version not announced before.
    var onNewVersion: ((Release) -> Void)?

    static let defaultFeed = URL(string: "https://raw.githubusercontent.com/atikorn-sub/P-Island/main/download/latest.json")!
    /// `--update-feed <url>` points at another file (for testing).
    private let feed: URL = {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--update-feed"), i + 1 < args.count, let url = URL(string: args[i + 1]) { return url }
        return defaultFeed
    }()
    private var timer: Timer?

    /// Checks shortly after launch and then every 24 hours, while `enabled()` says so.
    func startAutomaticChecks(enabled: @escaping () -> Bool) {
        let run = { [weak self] in
            guard enabled() else { return }
            self?.check(announce: true)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: run)
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { _ in run() }
    }

    /// `announce`: tell `onNewVersion` about a release, once per version.
    func check(announce: Bool = false) {
        guard status != .checking else { return }
        status = .checking
        var request = URLRequest(url: feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("P Island \(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            let release = data.flatMap { try? JSONDecoder().decode(Release.self, from: $0) }
            DispatchQueue.main.async {
                guard let release else {
                    self.status = .failed
                    return
                }
                guard Self.isNewer(release.version, than: AppInfo.version) else {
                    self.status = .upToDate
                    return
                }
                self.status = .available(release)
                NSLog("%@", "Islet update: \(release.version) available (this is \(AppInfo.version))")
                let key = "announcedVersion"
                if announce, UserDefaults.standard.string(forKey: key) != release.version {
                    UserDefaults.standard.set(release.version, forKey: key)
                    self.onNewVersion?(release)
                }
            }
        }.resume()
    }

    /// "1.10" is newer than "1.9"; missing parts count as 0.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}
