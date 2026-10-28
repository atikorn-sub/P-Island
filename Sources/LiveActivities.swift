import AppKit
import CoreAudio
import CoreMediaIO

// MARK: - Caps Lock

/// Notices Caps Lock going on or off. Reading the modifier state needs no permission, unlike watching keys;
/// four looks a second cost next to nothing.
final class CapsLockMonitor {
    var onChange: ((Bool) -> Void)?
    private var isOn = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    private var timer: Timer?

    init() {
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func check() {
        let now = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        guard now != isOn else { return }
        isOn = now
        onChange?(now)
    }
}

// MARK: - Camera and microphone

/// Tells when any app starts or stops using the camera or a microphone (the same thing macOS's green
/// and orange dots show). Which app it is isn't something macOS shares.
final class PrivacyMonitor {
    enum Device { case camera, microphone }

    /// (device, in use)
    var onChange: ((Device, Bool) -> Void)?
    /// P Island's own mirror doesn't count.
    var ignoreCamera: () -> Bool = { false }

    private var cameraOn = false
    private var micOn = false
    private var timer: Timer?

    init() {
        cameraOn = Self.cameraInUse()
        micOn = Self.microphoneInUse()
        // Device listeners would need re-attaching whenever devices come and go; a slow look is simpler.
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.check() }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func check() {
        let camera = Self.cameraInUse() && !ignoreCamera()
        if camera != cameraOn {
            cameraOn = camera
            onChange?(.camera, camera)
        }
        let mic = Self.microphoneInUse()
        if mic != micOn {
            micOn = mic
            onChange?(.microphone, mic)
        }
    }

    private static func cameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == 0, size > 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &ids) == 0 else { return false }
        return ids.contains { id in
            var running = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                    mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                                    mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var value: UInt32 = 0
            var got: UInt32 = 0
            return CMIOObjectGetPropertyData(id, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &got, &value) == 0 && value != 0
        }
    }

    private static func microphoneInUse() -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return false }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return false }
        return ids.contains { id in
            // Real inputs only: aggregates are plumbing (P Island's own waveform tap is one).
            guard hasInput(id), uint(id, kAudioDevicePropertyTransportType) != kAudioDeviceTransportTypeAggregate else { return false }
            var running = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                                     mScope: kAudioDevicePropertyScopeInput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var value: UInt32 = 0
            var valueSize = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(id, &running, 0, nil, &valueSize, &value) == noErr && value != 0
        }
    }

    private static func hasInput(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func uint(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value)
        return value
    }
}

// MARK: - Downloads

/// Watches the Downloads folder for files still being downloaded (Chrome's .crdownload, Safari's .download,
/// Firefox's .part) and reports their progress, and when they finish.
final class DownloadMonitor: ObservableObject {
    struct Download: Equatable {
        let partial: URL
        var name: String
        var bytes: Int64
        /// Safari knows the total; Chrome and Firefox don't say.
        var total: Int64?
        var bytesPerSecond: Double = 0

        var fraction: Double? { total.flatMap { $0 > 0 ? min(1, Double(bytes) / Double($0)) : nil } }
    }

    @Published private(set) var downloads: [Download] = []
    var onFinished: ((URL) -> Void)?

    /// The one to show: the biggest still going.
    var primary: Download? { downloads.max { ($0.total ?? $0.bytes) < ($1.total ?? $1.bytes) } }

    private static let partialExtensions = ["crdownload", "download", "part", "opdownload"]
    private let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    private var source: DispatchSourceFileSystemObject?
    private var poll: Timer?

    func start() {
        guard source == nil else { return }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in self?.scan() }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
        scan()
    }

    func stop() {
        source?.cancel()
        source = nil
        poll?.invalidate()
        poll = nil
        downloads = []
    }

    /// Looks at the folder; while something is downloading, again every second for sizes and speed.
    private func scan() {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        let partials = names.filter { Self.partialExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .map { folder.appendingPathComponent($0) }

        var next: [Download] = []
        for url in partials {
            let (bytes, total) = Self.progress(of: url)
            var d = downloads.first { $0.partial == url } ?? Download(partial: url, name: Self.finalName(url), bytes: 0, total: nil)
            let grown = Double(bytes - d.bytes)
            d.bytesPerSecond = d.bytes > 0 ? max(0, d.bytesPerSecond * 0.6 + grown * 0.4) : 0
            d.bytes = bytes
            d.total = total
            next.append(d)
        }
        // A partial file that vanished either finished (its final file is there) or was renamed
        // (Chrome's "Unconfirmed 1234.crdownload") or cancelled; only the first is news.
        for gone in downloads where !partials.contains(gone.partial) {
            let finished = folder.appendingPathComponent(gone.name)
            if fm.fileExists(atPath: finished.path) { onFinished?(finished) }
        }
        if next != downloads { downloads = next }

        if next.isEmpty {
            poll?.invalidate()
            poll = nil
        } else if poll == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.scan() }
            RunLoop.main.add(t, forMode: .common)
            poll = t
        }
    }

    /// "report.pdf.crdownload" → "report.pdf"; Safari's bundle keeps the real name inside.
    private static func finalName(_ url: URL) -> String {
        if url.pathExtension == "download", let name = safariInfo(url)?["DownloadEntryPath"] as? String {
            return (name as NSString).lastPathComponent
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private static func progress(of url: URL) -> (Int64, Int64?) {
        if url.pathExtension == "download", let info = safariInfo(url) {
            let done = (info["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value ?? 0
            let total = (info["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value
            return (done, total)
        }
        return (Converter.size(url), nil)
    }

    private static func safariInfo(_ bundle: URL) -> [String: Any]? {
        NSDictionary(contentsOf: bundle.appendingPathComponent("Info.plist")) as? [String: Any]
    }
}
