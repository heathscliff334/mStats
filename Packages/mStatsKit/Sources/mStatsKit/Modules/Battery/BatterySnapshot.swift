import Foundation

public struct BatterySnapshot: Sendable {
    public let isPresent: Bool
    public let chargePercent: Double
    public let isCharging: Bool
    public let isOnACPower: Bool
    public let minutesRemaining: Int?
    /// nil when the AppleSmartBattery registry entry doesn't expose it (rare, but not guaranteed on every model).
    public let cycleCount: Int?
    /// nil when design/max capacity keys aren't available.
    public let healthPercent: Double?

    public static let unavailable = BatterySnapshot(
        isPresent: false, chargePercent: 0, isCharging: false, isOnACPower: true,
        minutesRemaining: nil, cycleCount: nil, healthPercent: nil
    )
}
