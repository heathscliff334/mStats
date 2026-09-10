import Foundation

public struct VolumeInfo: Sendable, Identifiable, Hashable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let totalBytes: UInt64
    public let availableBytes: UInt64
}

public struct DiskSnapshot: Sendable {
    public let volumes: [VolumeInfo]
    public let readBytesPerSec: Double
    public let writeBytesPerSec: Double
    public let peakReadBytesPerSec: Double
    public let peakWriteBytesPerSec: Double
    public let topProcesses: [ProcessSnapshot]
    /// Usage percentage of the boot ("/") volume, matching what a user
    /// means by "storage usage" — not an average across mounted volumes.
    public let primaryVolumeUsedPercent: Double?

    public static let empty = DiskSnapshot(
        volumes: [], readBytesPerSec: 0, writeBytesPerSec: 0,
        peakReadBytesPerSec: 0, peakWriteBytesPerSec: 0, topProcesses: [],
        primaryVolumeUsedPercent: nil
    )
}
