import Foundation
import Observation
import ServiceManagement
import os

public enum TemperatureUnit: String, CaseIterable, Sendable {
    case celsius, fahrenheit

    public func format(_ celsius: Double) -> String {
        switch self {
        case .celsius: return String(format: "%.0f°C", celsius)
        case .fahrenheit: return String(format: "%.0f°F", celsius * 9.0 / 5.0 + 32.0)
        }
    }
}

public enum ByteRateUnit: String, CaseIterable, Sendable {
    case bytesPerSecond, bitsPerSecond

    public func format(_ bytesPerSecond: Double) -> String {
        switch self {
        case .bytesPerSecond:
            return Self.humanReadable(bytesPerSecond, units: ["B/s", "KB/s", "MB/s", "GB/s"])
        case .bitsPerSecond:
            return Self.humanReadable(bytesPerSecond * 8, units: ["b/s", "Kb/s", "Mb/s", "Gb/s"])
        }
    }

    private static func humanReadable(_ value: Double, units: [String]) -> String {
        var value = value
        var index = 0
        while value >= 1024, index < units.count - 1 {
            value /= 1024
            index += 1
        }
        return String(format: "%.1f %@", value, units[index])
    }
}

/// Central, persisted app configuration. Every module's enabled flag and
/// poll interval lives here so both the MenuBarExtra scenes (which gate on
/// the `*Enabled` flags) and each module's ModuleViewModel (which reads the
/// matching `*PollInterval`) observe the same source of truth live.
@Observable
@MainActor
public final class AppSettings {
    public static let shared = AppSettings()

    private let defaults: UserDefaults
    private let logger = MetricLog.logger("AppSettings")

    public var cpuEnabled: Bool { didSet { defaults.set(cpuEnabled, forKey: Key.cpuEnabled) } }
    public var memoryEnabled: Bool { didSet { defaults.set(memoryEnabled, forKey: Key.memoryEnabled) } }
    public var diskEnabled: Bool { didSet { defaults.set(diskEnabled, forKey: Key.diskEnabled) } }
    public var networkEnabled: Bool { didSet { defaults.set(networkEnabled, forKey: Key.networkEnabled) } }
    public var sensorsEnabled: Bool { didSet { defaults.set(sensorsEnabled, forKey: Key.sensorsEnabled) } }
    public var batteryEnabled: Bool { didSet { defaults.set(batteryEnabled, forKey: Key.batteryEnabled) } }
    public var portsEnabled: Bool { didSet { defaults.set(portsEnabled, forKey: Key.portsEnabled) } }

    public var cpuPollInterval: Double { didSet { defaults.set(cpuPollInterval, forKey: Key.cpuPollInterval) } }
    public var memoryPollInterval: Double { didSet { defaults.set(memoryPollInterval, forKey: Key.memoryPollInterval) } }
    public var diskPollInterval: Double { didSet { defaults.set(diskPollInterval, forKey: Key.diskPollInterval) } }
    public var networkPollInterval: Double { didSet { defaults.set(networkPollInterval, forKey: Key.networkPollInterval) } }
    public var sensorsPollInterval: Double { didSet { defaults.set(sensorsPollInterval, forKey: Key.sensorsPollInterval) } }
    public var batteryPollInterval: Double { didSet { defaults.set(batteryPollInterval, forKey: Key.batteryPollInterval) } }
    public var portsPollInterval: Double { didSet { defaults.set(portsPollInterval, forKey: Key.portsPollInterval) } }

    /// Off by default: enabling this makes an outbound HTTPS call to a
    /// third-party IP-lookup service. Surfaced explicitly in Preferences.
    public var publicIPEnabled: Bool { didSet { defaults.set(publicIPEnabled, forKey: Key.publicIPEnabled) } }
    public var publicIPPollInterval: Double { didSet { defaults.set(publicIPPollInterval, forKey: Key.publicIPPollInterval) } }

    public var temperatureUnit: TemperatureUnit {
        didSet { defaults.set(temperatureUnit.rawValue, forKey: Key.temperatureUnit) }
    }
    public var byteRateUnit: ByteRateUnit {
        didSet { defaults.set(byteRateUnit.rawValue, forKey: Key.byteRateUnit) }
    }

    public var launchAtLoginEnabled: Bool {
        didSet {
            guard launchAtLoginEnabled != oldValue else { return }
            defaults.set(launchAtLoginEnabled, forKey: Key.launchAtLoginEnabled)
            applyLoginItemState()
        }
    }

    private enum Key {
        static let cpuEnabled = "cpuEnabled"
        static let memoryEnabled = "memoryEnabled"
        static let diskEnabled = "diskEnabled"
        static let networkEnabled = "networkEnabled"
        static let sensorsEnabled = "sensorsEnabled"
        static let batteryEnabled = "batteryEnabled"
        static let portsEnabled = "portsEnabled"
        static let cpuPollInterval = "cpuPollInterval"
        static let memoryPollInterval = "memoryPollInterval"
        static let diskPollInterval = "diskPollInterval"
        static let networkPollInterval = "networkPollInterval"
        static let sensorsPollInterval = "sensorsPollInterval"
        static let batteryPollInterval = "batteryPollInterval"
        static let portsPollInterval = "portsPollInterval"
        static let publicIPEnabled = "publicIPEnabled"
        static let publicIPPollInterval = "publicIPPollInterval"
        static let temperatureUnit = "temperatureUnit"
        static let byteRateUnit = "byteRateUnit"
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        func bool(_ key: String, default def: Bool) -> Bool {
            defaults.object(forKey: key) == nil ? def : defaults.bool(forKey: key)
        }
        func double(_ key: String, default def: Double) -> Double {
            defaults.object(forKey: key) == nil ? def : defaults.double(forKey: key)
        }

        cpuEnabled = bool(Key.cpuEnabled, default: true)
        memoryEnabled = bool(Key.memoryEnabled, default: true)
        diskEnabled = bool(Key.diskEnabled, default: true)
        networkEnabled = bool(Key.networkEnabled, default: true)
        sensorsEnabled = bool(Key.sensorsEnabled, default: true)
        batteryEnabled = bool(Key.batteryEnabled, default: true)
        portsEnabled = bool(Key.portsEnabled, default: true)

        cpuPollInterval = double(Key.cpuPollInterval, default: 1.0)
        memoryPollInterval = double(Key.memoryPollInterval, default: 2.0)
        diskPollInterval = double(Key.diskPollInterval, default: 3.0)
        networkPollInterval = double(Key.networkPollInterval, default: 1.0)
        sensorsPollInterval = double(Key.sensorsPollInterval, default: 3.0)
        batteryPollInterval = double(Key.batteryPollInterval, default: 5.0)
        portsPollInterval = double(Key.portsPollInterval, default: 4.0)

        publicIPEnabled = bool(Key.publicIPEnabled, default: false)
        publicIPPollInterval = double(Key.publicIPPollInterval, default: 300.0)

        temperatureUnit = TemperatureUnit(rawValue: defaults.string(forKey: Key.temperatureUnit) ?? "") ?? .celsius
        byteRateUnit = ByteRateUnit(rawValue: defaults.string(forKey: Key.byteRateUnit) ?? "") ?? .bytesPerSecond

        launchAtLoginEnabled = bool(Key.launchAtLoginEnabled, default: false)
    }

    private func applyLoginItemState() {
        do {
            if launchAtLoginEnabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            logger.error("Failed to update login item state: \(String(describing: error), privacy: .public)")
        }
    }
}
