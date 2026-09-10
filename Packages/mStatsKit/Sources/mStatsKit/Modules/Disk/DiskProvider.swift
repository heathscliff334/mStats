import Foundation

public actor DiskProvider: SystemMetricProvider {
    private let reader = DiskIOKitReader()
    private var previousRead: UInt64?
    private var previousWrite: UInt64?
    private var previousTimestamp: ContinuousClock.Instant?
    private var peakRead: Double = 0
    private var peakWrite: Double = 0

    public init() {}

    public func poll() async -> DiskSnapshot {
        let volumes = Self.readVolumes()
        let (cumulativeRead, cumulativeWrite) = reader.cumulativeBytes()
        let now = ContinuousClock.now

        var readPerSec = 0.0
        var writePerSec = 0.0
        if let prevRead = previousRead, let prevWrite = previousWrite, let prevTime = previousTimestamp {
            let duration = now - prevTime
            let elapsed = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
            if elapsed > 0 {
                if cumulativeRead >= prevRead { readPerSec = Double(cumulativeRead - prevRead) / elapsed }
                if cumulativeWrite >= prevWrite { writePerSec = Double(cumulativeWrite - prevWrite) / elapsed }
            }
        }
        previousRead = cumulativeRead
        previousWrite = cumulativeWrite
        previousTimestamp = now
        peakRead = max(peakRead, readPerSec)
        peakWrite = max(peakWrite, writePerSec)

        let topProcesses = await ProcessSnapshotProvider.shared
            .currentSnapshots(minimumInterval: 2.0)
            .sorted { ($0.diskBytesReadPerSec + $0.diskBytesWrittenPerSec) > ($1.diskBytesReadPerSec + $1.diskBytesWrittenPerSec) }
            .prefix(5)

        return DiskSnapshot(
            volumes: volumes,
            readBytesPerSec: readPerSec,
            writeBytesPerSec: writePerSec,
            peakReadBytesPerSec: peakRead,
            peakWriteBytesPerSec: peakWrite,
            topProcesses: Array(topProcesses),
            primaryVolumeUsedPercent: Self.readPrimaryVolumeUsedPercent()
        )
    }

    // Deliberately using the raw `.volumeAvailableCapacityKey`, NOT the
    // "ForImportantUsage" variant: the latter is a conservative pre-flight
    // estimate for "is it safe to write N bytes" (it reserves headroom),
    // and reads much higher than actual free space — it disagreed with
    // `diskutil`/`df` by ~14 percentage points when validated on-device.
    private static func readPrimaryVolumeUsedPercent() -> Double? {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0 else {
            return nil
        }
        let available = values.volumeAvailableCapacity ?? 0
        return DiskMath.usedPercent(totalBytes: UInt64(total), availableBytes: UInt64(max(0, available)))
    }

    private static func readVolumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsInternalKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            return []
        }
        return urls.compactMap { url -> VolumeInfo? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            guard let total = values.volumeTotalCapacity, total > 0 else { return nil }
            let available = values.volumeAvailableCapacity ?? 0
            return VolumeInfo(
                path: url.path,
                name: values.volumeName ?? url.lastPathComponent,
                totalBytes: UInt64(total),
                availableBytes: UInt64(max(0, available))
            )
        }
    }
}
