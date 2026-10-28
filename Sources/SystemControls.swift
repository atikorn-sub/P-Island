import AppKit
import AudioToolbox
import CoreAudio

/// Output volume (CoreAudio) and built-in display brightness, with change callbacks for the notch HUD.
final class SystemControls: ObservableObject {
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

    // MARK: Brightness

    func setBrightness(_ value: Float) {
        guard let setBrightnessFn, let display = builtInDisplay else { return }
        let v = min(1, max(0, value))
        _ = setBrightnessFn(display, v)
        brightness = v
    }

    /// Brightness before the mirror's light turned it up, to put back afterwards.
    private var brightnessBeforeBoost: Float?

    /// Full brightness while the mirror's light is on; the previous level comes back after (also on quit).
    func boostBrightness(_ on: Bool) {
        if on {
            if brightnessBeforeBoost == nil { brightnessBeforeBoost = brightness }
            setBrightness(1)
        } else if let saved = brightnessBeforeBoost {
            setBrightness(saved)
            brightnessBeforeBoost = nil
        }
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
