import Foundation

public enum MemoryPressureLevel: Sendable {
    case normal, warning, critical
}

public struct MemorySnapshot: Sendable {
    public let totalBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    /// internal_page_count - purgeable_count, i.e. real non-reclaimable app
    /// memory. Validated against Activity Monitor's "App Memory" bucket.
    public let appBytes: UInt64
    /// external_page_count - purgeable_count: reclaimable file-backed cache
    /// (Activity Monitor's "Cached Files"). Not counted as "used".
    public let cachedFilesBytes: UInt64
    public let freeBytes: UInt64
    public let swapUsedBytes: UInt64
    public let swapTotalBytes: UInt64
    public let pressureLevel: MemoryPressureLevel
    public let topProcesses: [ProcessSnapshot]

    /// Matches Activity Monitor's "Memory Used": App + Wired + Compressed,
    /// excluding Free and reclaimable Cached Files.
    public var usedFraction: Double {
        MemoryMath.usedFraction(total: totalBytes, wired: wiredBytes, compressed: compressedBytes, app: appBytes)
    }

    public static let empty = MemorySnapshot(
        totalBytes: 0, wiredBytes: 0, compressedBytes: 0, appBytes: 0,
        cachedFilesBytes: 0, freeBytes: 0, swapUsedBytes: 0, swapTotalBytes: 0,
        pressureLevel: .normal, topProcesses: []
    )
}
