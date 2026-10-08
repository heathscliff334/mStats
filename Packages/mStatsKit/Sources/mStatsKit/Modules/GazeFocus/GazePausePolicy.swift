import CoreGraphics
import Foundation

public enum GazePauseReason: String, Sendable, Equatable {
    case singleDisplay
    case screenLocked
    case displaysAsleep
    case systemAsleep
    case lowPowerMode
    case cameraUnavailable

    public var message: String {
        switch self {
        case .singleDisplay: "Needs 2 or more separate displays"
        case .screenLocked: "Screen is locked"
        case .displaysAsleep: "Displays are asleep"
        case .systemAsleep: "Mac is asleep"
        case .lowPowerMode: "Paused in Low Power Mode"
        case .cameraUnavailable: "Camera unavailable"
        }
    }
}

public enum GazePausePolicy {
    /// Precedence runs from "nothing is running at all" down to "could be
    /// running but chose not to", so the reason shown is the most fundamental.
    public static func reason(
        distinctDisplayCount: Int,
        screenLocked: Bool,
        displaysAsleep: Bool,
        systemAsleep: Bool,
        lowPowerMode: Bool,
        pauseOnLowPower: Bool,
        cameraInterrupted: Bool
    ) -> GazePauseReason? {
        if systemAsleep { return .systemAsleep }
        if displaysAsleep { return .displaysAsleep }
        if screenLocked { return .screenLocked }
        if distinctDisplayCount < 2 { return .singleDisplay }
        if cameraInterrupted { return .cameraUnavailable }
        if lowPowerMode, pauseOnLowPower { return .lowPowerMode }
        return nil
    }
}

public enum DisplayTopology {
    /// Mirrored displays report separate IDs but share a frame, and behave as
    /// one screen. Counting distinct frames (not IDs) is what makes the
    /// "fewer than 2 displays" pause correct for a mirrored setup.
    public static func distinctDisplayCount(bounds: [CGRect]) -> Int {
        var unique: [CGRect] = []
        for rect in bounds where !unique.contains(rect) {
            unique.append(rect)
        }
        return unique.count
    }
}
