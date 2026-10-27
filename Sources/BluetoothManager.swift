import Foundation
import IOBluetooth

/// Reports Bluetooth devices connecting and disconnecting, with AirPods battery levels when available.
final class BluetoothManager: NSObject {
    /// (name, kind, connected, battery text such as "L 80% · R 85% · เคส 60%")
    var onEvent: ((String, BluetoothKind, Bool, String?) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    /// Devices already connected at launch are reported to us too; stay quiet about those.
    private let quietUntil = Date().addingTimeInterval(4)

    override init() {
        super.init()
        connectNotification = IOBluetoothDevice.register(forConnectNotifications: self,
                                                         selector: #selector(deviceConnected(_:device:)))
    }

    @objc private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = device.addressString ?? UUID().uuidString
        disconnectNotifications[address] = device.register(forDisconnectNotification: self,
                                                           selector: #selector(deviceDisconnected(_:device:)))
        guard Date() > quietUntil else { return }
        // Battery levels arrive a moment after the connection.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.onEvent?(Self.name(of: device), Self.kind(of: device), true, Self.battery(of: device))
        }
    }

    @objc private func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        note.unregister()
        if let address = device.addressString { disconnectNotifications[address] = nil }
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(Self.name(of: device), Self.kind(of: device), false, nil)
        }
    }

    private static func name(of device: IOBluetoothDevice) -> String {
        device.name ?? device.nameOrAddress ?? "Bluetooth device"
    }

    private static func kind(of device: IOBluetoothDevice) -> BluetoothKind {
        let name = (device.name ?? "").lowercased()
        if name.contains("airpods max") { return .airpodsMax }
        if name.contains("airpods pro") { return .airpodsPro }
        if name.contains("airpods") { return .airpods }
        if name.contains("trackpad") { return .trackpad }
        switch device.deviceClassMajor {
        case UInt32(kBluetoothDeviceClassMajorAudio):
            return device.deviceClassMinor == UInt32(kBluetoothDeviceClassMinorAudioLoudspeaker) ? .speaker : .headphones
        case UInt32(kBluetoothDeviceClassMajorPeripheral):
            let minor = device.deviceClassMinor
            if minor & 0x10 != 0 { return .keyboard }
            if minor & 0x20 != 0 { return .mouse }
            return .gamepad
        default:
            return .other
        }
    }

    /// Apple headphones expose these undocumented properties; other devices simply don't respond.
    private static func battery(of device: IOBluetoothDevice) -> String? {
        func percent(_ key: String) -> Int? {
            guard device.responds(to: NSSelectorFromString(key)),
                  let value = device.value(forKey: key) as? NSNumber, value.intValue > 0 else { return nil }
            return value.intValue
        }
        let parts = [
            percent("batteryPercentLeft").map { "L \($0)%" },
            percent("batteryPercentRight").map { "R \($0)%" },
            percent("batteryPercentCase").map { "เคส \($0)%" },
        ].compactMap { $0 }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        return percent("batteryPercentSingle").map { "แบต \($0)%" }
    }
}
