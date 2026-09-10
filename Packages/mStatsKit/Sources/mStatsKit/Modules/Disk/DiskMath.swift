import Foundation

/// Pure percentage math extracted from DiskProvider so it's testable
/// without a live `resourceValues` filesystem call.
enum DiskMath {
    static func usedPercent(totalBytes: UInt64, availableBytes: UInt64) -> Double? {
        guard totalBytes > 0 else { return nil }
        let used = totalBytes > availableBytes ? totalBytes - availableBytes : 0
        return Double(used) / Double(totalBytes) * 100
    }
}
