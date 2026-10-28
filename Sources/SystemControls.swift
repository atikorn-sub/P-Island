import AppKit
import AudioToolbox
import CoreAudio

/// A speaker, headphones or screen the Mac can play sound through.
struct AudioOutput: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
    let symbol: String
}

/// Output volume and device (CoreAudio) and built-in display brightness, with change callbacks for the notch HUD.
final class SystemControls: ObservableObject {
    /// Every output that can play sound, built-in first.
    @Published private(set) var outputs: [AudioOutput] = []
    /// The output sound plays through now.
    @Published private(set) var currentOutput = AudioObjectID(kAudioObjectUnknown)
    @Published private(set) var volume: Float = 0
    @Published private(set) var muted = false
    /// nil when no built-in display reports brightness (e.g. lid closed).
    @Published private(set) var brightness: Float?

    var onVolumeChange: (() -> Void)?
    var onBrightnessChange: (() -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var listenedDevices: Set<AudioObjectID> = []
    private var brightnessTimer: Timer?

    // DisplayServices is private but is what the system brightness keys use for the built-in display.
    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private var getBrightnessFn: GetBrightnessFn?
    private var setBrightnessFn: SetBrightnessFn?

    init() {
        loadDisplayServices()
        attachDefaultOutput()
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            self?.attachDefaultOutput()
        }
        loadOutputs()
        var devices = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &devices, .main) { [weak self] _, _ in
            self?.loadOutputs()
        }
        brightness = readBrightness()
        // Brightness has no change notification, so poll gently.
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.pollBrightness() }
        RunLoop.main.add(timer, forMode: .common)
        brightnessTimer = timer
    }

    // MARK: Volume

    func setVolume(_ value: Float) {
        var v = Float32(min(1, max(0, value)))
        var address = volumeAddress
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        if muted && v > 0 {
            var off: UInt32 = 0
            var muteAddress = self.muteAddress
            AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &off)
        }
    }

    private var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                   mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private func attachDefaultOutput() {
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr else { return }
        device = id
        if currentOutput != id { currentOutput = id }
        readVolume(notify: false)
        guard !listenedDevices.contains(id) else { return }
        listenedDevices.insert(id)
        for var addr in [volumeAddress, muteAddress] {
            AudioObjectAddPropertyListenerBlock(id, &addr, .main) { [weak self] _, _ in
                guard let self, self.device == id else { return }
                self.readVolume(notify: true)
            }
        }
    }

    private func readVolume(notify: Bool) {
        var v = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = volumeAddress
        let hasVolume = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &v) == noErr
        var m: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        var muteAddress = self.muteAddress
        _ = AudioObjectGetPropertyData(device, &muteAddress, 0, nil, &size, &m)
        let changed = (hasVolume && abs(v - volume) > 0.001) || (m != 0) != muted
        if hasVolume { volume = v }
        muted = m != 0
        if notify && changed { onVolumeChange?() }
    }

    // MARK: Output device

    /// Sends all sound, alerts included, to `output`.
    func setOutput(_ output: AudioOutput) {
        var id = output.id
        let size = UInt32(MemoryLayout<AudioObjectID>.size)
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                     mElement: kAudioObjectPropertyElementMain)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, size, &id)
        }
    }

    private func loadOutputs() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return }

        let found: [(AudioOutput, UInt32)] = ids.compactMap { id in
            guard Self.hasOutputStreams(id), !Self.flag(id, kAudioDevicePropertyIsHidden) else { return nil }
            let transport = Self.uint(id, kAudioDevicePropertyTransportType)
            // Aggregates are plumbing (e.g. the waveform's own tap), not something to pick.
            guard transport != kAudioDeviceTransportTypeAggregate, let name = Self.name(id) else { return nil }
            return (AudioOutput(id: id, name: name, symbol: Self.symbol(transport: transport, name: name)), transport)
        }
        let sorted = found.sorted { a, b in
            let builtInA = a.1 == kAudioDeviceTransportTypeBuiltIn, builtInB = b.1 == kAudioDeviceTransportTypeBuiltIn
            return builtInA != builtInB ? builtInA : a.0.name.localizedCompare(b.0.name) == .orderedAscending
        }.map(\.0)
        if outputs != sorted { outputs = sorted }
    }

    private static func symbol(transport: UInt32, name: String) -> String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return "laptopcomputer"
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            let n = name.lowercased()
            if n.contains("airpods max") { return "airpodsmax" }
            if n.contains("airpods pro") { return "airpodspro" }
            if n.contains("airpods") { return "airpods" }
            return "headphones"
        case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return "tv"
        case kAudioDeviceTransportTypeAirPlay: return "airplayaudio"
        default: return "hifispeaker"
        }
    }

    private static func hasOutputStreams(_ id: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeOutput,
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

    private static func flag(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        uint(id, selector) != 0
    }

    private static func name(_ id: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &name) == noErr,
              let value = name?.takeRetainedValue() as String?, !value.isEmpty else { return nil }
        return value
    }

    // MARK: Brightness

    func setBrightness(_ value: Float) {
        guard let setBrightnessFn, let display = builtInDisplay else { return }
        let v = min(1, max(0, value))
        _ = setBrightnessFn(display, v)
        brightness = v
    }

    private func loadDisplayServices() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else { return }
        if let get = dlsym(handle, "DisplayServicesGetBrightness") {
            getBrightnessFn = unsafeBitCast(get, to: GetBrightnessFn.self)
        }
        if let set = dlsym(handle, "DisplayServicesSetBrightness") {
            setBrightnessFn = unsafeBitCast(set, to: SetBrightnessFn.self)
        }
    }

    private var builtInDisplay: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(8, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    private func readBrightness() -> Float? {
        guard let getBrightnessFn, let display = builtInDisplay else { return nil }
        var v: Float = 0
        return getBrightnessFn(display, &v) == 0 ? v : nil
    }

    private func pollBrightness() {
        guard let new = readBrightness() else { return }
        let old = brightness
        brightness = new
        // A key press moves brightness by 1/16; ignore the slow drift of auto-brightness.
        if let old, abs(new - old) >= 0.03 { onBrightnessChange?() }
    }
}
