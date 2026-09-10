import Foundation
import Darwin
import Dispatch

/// Persistent listener for the official memory-pressure notification API.
/// DispatchSourceMemoryPressure is edge-triggered (fires on level changes),
/// not a "read current value now" API, so this keeps the last-seen level
/// around for MemoryProvider to read on each poll instead of guessing from
/// free-byte ratios.
private final class MemoryPressureMonitor: @unchecked Sendable {
    static let shared = MemoryPressureMonitor()

    private let source: DispatchSourceMemoryPressure
    private let lock = NSLock()
    private var _level: MemoryPressureLevel = .normal

    var level: MemoryPressureLevel {
        lock.lock()
        defer { lock.unlock() }
        return _level
    }

    private init() {
        source = DispatchSource.makeMemoryPressureSource(eventMask: .all, queue: .global(qos: .utility))
        source.setEventHandler { [weak source] in
            guard let data = source?.data else { return }
            let level: MemoryPressureLevel = data.contains(.critical) ? .critical
                : data.contains(.warning) ? .warning : .normal
            MemoryPressureMonitor.shared.update(level)
        }
        source.resume()
    }

    private func update(_ level: MemoryPressureLevel) {
        lock.lock()
        _level = level
        lock.unlock()
    }
}

public struct MemoryProvider: SystemMetricProvider {
    public init() {
        _ = MemoryPressureMonitor.shared // start listening immediately
    }

    public func poll() async -> MemorySnapshot {
        guard let vmStats = Self.readVMStatistics() else { return .empty }
        let pageSize = UInt64(Self.pageSize())
        let total = Self.physicalMemory()

        let breakdown = MemoryMath.breakdown(
            pageSize: pageSize,
            freeCount: UInt64(vmStats.free_count),
            speculativeCount: UInt64(vmStats.speculative_count),
            wireCount: UInt64(vmStats.wire_count),
            compressorPageCount: UInt64(vmStats.compressor_page_count),
            externalPageCount: UInt64(vmStats.external_page_count),
            internalPageCount: UInt64(vmStats.internal_page_count),
            purgeableCount: UInt64(vmStats.purgeable_count)
        )

        let (swapUsed, swapTotal) = Self.readSwapUsage()

        let topProcesses = await ProcessSnapshotProvider.shared
            .currentSnapshots(minimumInterval: 2.0)
            .sorted { $0.residentMemoryBytes > $1.residentMemoryBytes }
            .prefix(5)

        return MemorySnapshot(
            totalBytes: total,
            wiredBytes: breakdown.wired,
            compressedBytes: breakdown.compressed,
            appBytes: breakdown.app,
            cachedFilesBytes: breakdown.cachedFiles,
            freeBytes: breakdown.free,
            swapUsedBytes: swapUsed,
            swapTotalBytes: swapTotal,
            pressureLevel: MemoryPressureMonitor.shared.level,
            topProcesses: Array(topProcesses)
        )
    }

    private static func pageSize() -> Int {
        var size: vm_size_t = 0
        host_page_size(mach_host_self(), &size)
        return Int(size)
    }

    private static func physicalMemory() -> UInt64 {
        var size: UInt64 = 0
        var sizeLen = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &sizeLen, nil, 0)
        return size
    }

    private static func readVMStatistics() -> vm_statistics64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return stats
    }

    private static func readSwapUsage() -> (used: UInt64, total: UInt64) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return (0, 0) }
        return (usage.xsu_used, usage.xsu_total)
    }
}
