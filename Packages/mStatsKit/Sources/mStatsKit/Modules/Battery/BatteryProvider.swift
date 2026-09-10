import Foundation
import IOKit
import IOKit.ps

/// Charge/time-remaining come from the official IOPowerSources API (stable
/// across macOS versions). Cycle count and health % require reading the
/// AppleSmartBattery IORegistry entry directly — documented keys, but with
/// a couple of naming fallbacks since they've drifted slightly across
/// macOS/Apple Silicon vs Intel.
public struct BatteryProvider: SystemMetricProvider {
    public init() {}

    public func poll() async -> BatterySnapshot {
        Self.readPowerSource() ?? .unavailable
    }

    private static func readPowerSource() -> BatterySnapshot? {
        let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        guard let sourcesList = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = sourcesList.first,
              let description = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any]
        else {
            return nil
        }

        let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int ?? 0
        let maxCapacity = description[kIOPSMaxCapacityKey] as? Int ?? 100
        let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        let powerState = description[kIOPSPowerSourceStateKey] as? String
        let timeToEmpty = description[kIOPSTimeToEmptyKey] as? Int
        let timeToFull = description[kIOPSTimeToFullChargeKey] as? Int

        let chargePercent = maxCapacity > 0
            ? Double(currentCapacity) / Double(maxCapacity) * 100
            : Double(currentCapacity)

        let (cycleCount, healthPercent) = readSmartBatteryRegistry()

        return BatterySnapshot(
            isPresent: true,
            chargePercent: chargePercent,
            isCharging: isCharging,
            isOnACPower: powerState == kIOPSACPowerValue,
            minutesRemaining: isCharging ? timeToFull : timeToEmpty,
            cycleCount: cycleCount,
            healthPercent: healthPercent
        )
    }

    private static func readSmartBatteryRegistry() -> (cycleCount: Int?, healthPercent: Double?) {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return (nil, nil) }
        defer { IOObjectRelease(service) }

        var propertiesUnmanaged: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &propertiesUnmanaged, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let propertiesUnmanaged else { return (nil, nil) }
        let properties = propertiesUnmanaged.takeRetainedValue() as? [String: Any] ?? [:]

        let cycleCount = properties["CycleCount"] as? Int
        let designCapacity = properties["DesignCapacity"] as? Int
        let maxCapacity = (properties["AppleRawMaxCapacity"] as? Int) ?? (properties["MaxCapacity"] as? Int)

        var health: Double?
        if let designCapacity, let maxCapacity, designCapacity > 0 {
            health = Double(maxCapacity) / Double(designCapacity) * 100
        }
        return (cycleCount, health)
    }
}
