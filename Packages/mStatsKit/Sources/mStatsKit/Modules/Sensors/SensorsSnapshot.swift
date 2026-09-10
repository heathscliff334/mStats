import Foundation

public struct FanReading: Sendable, Identifiable {
    public var id: Int { index }
    public let index: Int
    public let currentRPM: Double
    public let targetRPM: Double
}

public struct SensorsSnapshot: Sendable {
    public let cpuTemperatureCelsius: Double?
    public let gpuTemperatureCelsius: Double?
    public let batteryTemperatureCelsius: Double?
    /// Empty on fanless models (MacBook Air) — not an error, `FNum` is
    /// legitimately 0 there.
    public let fans: [FanReading]

    public static let empty = SensorsSnapshot(
        cpuTemperatureCelsius: nil, gpuTemperatureCelsius: nil,
        batteryTemperatureCelsius: nil, fans: []
    )
}
