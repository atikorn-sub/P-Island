import AudioToolbox
import CoreAudio
import Foundation

/// Live loudness of whatever the Mac is playing, through a Core Audio process tap (macOS 14.2+).
/// Opt-in: starting it asks for the "System Audio Recording" permission. Audio is only measured, never stored.
final class AudioLevelMonitor: ObservableObject {
    /// Four bar heights, 0…1, roughly bass → treble.
    @Published private(set) var levels: [Float] = [0, 0, 0, 0]
    @Published private(set) var isRunning = false

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "islet.audio-levels", qos: .userInteractive)

    // Touched only on `queue`.
    private var lowPass: Float = 0
    private var previous: Float = 0
    private var smoothed: [Float] = [0, 0, 0, 0]
    private var lastPublish = DispatchTime.now()

    init() {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            guard let self, self.isRunning else { return }
            self.stop()
            self.start()
        }
    }

    func start() {
        guard !isRunning else { return }
        guard #available(macOS 14.2, *) else { return }
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr else {
            NSLog("%@", "Islet: audio tap unavailable")
            return
        }
        tapID = tap

        let outputUID = Self.defaultOutputUID() ?? ""
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "P Island Levels",
            kAudioAggregateDeviceUIDKey: "com.atikorn.islet.levels.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregate) == noErr else {
            cleanUp()
            return
        }
        aggregateID = aggregate

        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, queue) { [weak self] _, input, _, _, _ in
            self?.measure(input)
        }
        guard status == noErr, let proc else {
            cleanUp()
            return
        }
        procID = proc
        guard AudioDeviceStart(aggregate, proc) == noErr else {
            cleanUp()
            return
        }
        isRunning = true
    }

    func stop() {
        cleanUp()
        isRunning = false
        levels = [0, 0, 0, 0]
    }

    private func cleanUp() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown, #available(macOS 14.2, *) {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    /// Cheap four-band meter: a low-pass for bass, the sample-to-sample change for treble, and the overall level between.
    private func measure(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        var sum: Float = 0, bassSum: Float = 0, trebleSum: Float = 0
        var count = 0
        for buffer in buffers {
            guard let data = buffer.mData else { continue }
            let samples = data.assumingMemoryBound(to: Float32.self)
            let n = Int(buffer.mDataByteSize) / MemoryLayout<Float32>.size
            for i in 0..<n {
                let x = samples[i]
                lowPass += 0.03 * (x - lowPass)
                let diff = x - previous
                previous = x
                sum += x * x
                bassSum += lowPass * lowPass
                trebleSum += diff * diff
            }
            count += n
        }
        guard count > 0 else { return }
        let rms = sqrt(sum / Float(count))
        let bass = sqrt(bassSum / Float(count)) * 2.5
        let treble = sqrt(trebleSum / Float(count)) * 1.5
        let mid = max(0, rms - bass * 0.3)
        let raw = [bass, rms, mid, treble].map { Self.normalise($0) }
        for i in 0..<4 {
            // Rise quickly, fall slowly, like a VU meter.
            let speed: Float = raw[i] > smoothed[i] ? 0.6 : 0.15
            smoothed[i] += speed * (raw[i] - smoothed[i])
        }
        let now = DispatchTime.now()
        guard now.uptimeNanoseconds - lastPublish.uptimeNanoseconds > 33_000_000 else { return }
        lastPublish = now
        let snapshot = smoothed
        DispatchQueue.main.async { self.levels = snapshot }
    }

    /// −50 dB … 0 dB → 0 … 1
    private static func normalise(_ rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        return min(1, max(0, (20 * log10(rms) + 50) / 50))
    }

    private static func defaultOutputUID() -> String? {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return nil }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }
}
