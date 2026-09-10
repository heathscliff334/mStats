import Foundation
import CSystemShims

/// One process's resource usage at a point in time. `cpuUsagePercent` follows
/// Activity Monitor's convention: normalized to a single core, so a
/// multi-threaded process can exceed 100%.
public struct ProcessSnapshot: Sendable, Identifiable, Hashable {
    public var id: pid_t { pid }
    public let pid: pid_t
    public let name: String
    public let cpuUsagePercent: Double
    public let residentMemoryBytes: UInt64
    public let diskBytesReadPerSec: Double
    public let diskBytesWrittenPerSec: Double
}

/// Walks the process table once per cadence and caches the result so CPU,
/// Memory and Disk "top processes" views share a single `proc_listpids` /
/// `proc_pidinfo` / `proc_pid_rusage` walk instead of each doing their own.
public actor ProcessSnapshotProvider {
    public static let shared = ProcessSnapshotProvider()

    private struct PrevStats {
        var cpuTicksNanoseconds: UInt64
        var diskRead: UInt64
        var diskWrite: UInt64
        var timestamp: ContinuousClock.Instant
    }

    private var previous: [pid_t: PrevStats] = [:]
    private var lastSnapshots: [ProcessSnapshot] = []
    private var lastPollTime: ContinuousClock.Instant?

    private let machTimebaseRatio: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        guard info.denom != 0 else { return 1.0 }
        return Double(info.numer) / Double(info.denom)
    }()

    public init() {}

    /// Returns the cached table if it was refreshed within `minimumInterval`
    /// seconds ago, otherwise performs a fresh walk. Callers with different
    /// poll cadences (CPU at 1s, Disk at 2-5s) naturally share one walk this way.
    public func currentSnapshots(minimumInterval: TimeInterval = 1.5) -> [ProcessSnapshot] {
        let now = ContinuousClock.now
        if let last = lastPollTime, (now - last) < .seconds(minimumInterval) {
            return lastSnapshots
        }
        lastPollTime = now
        let snapshots = refresh(now: now)
        lastSnapshots = snapshots
        return snapshots
    }

    private func refresh(now: ContinuousClock.Instant) -> [ProcessSnapshot] {
        let pids = Self.listPIDs()
        var results: [ProcessSnapshot] = []
        results.reserveCapacity(pids.count)
        var stillAlive = Set<pid_t>()

        for pid in pids {
            guard pid > 0 else { continue }

            var taskInfo = proc_taskinfo()
            let taskInfoSize = Int32(MemoryLayout<proc_taskinfo>.size)
            let taskResult = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskInfoSize)
            guard taskResult == taskInfoSize else { continue }
            stillAlive.insert(pid)

            let totalTicks = taskInfo.pti_total_user + taskInfo.pti_total_system
            let totalNanoseconds = UInt64(Double(totalTicks) * machTimebaseRatio)

            // proc_pid_rusage's `rusage_info_t *buffer` parameter is really
            // "write struct data directly at this address" despite the
            // double-pointer typedef (rusage_info_t == void*) — the C idiom
            // is `(rusage_info_t *)&rusage`, a type-punned cast of the
            // struct's own address, NOT a separate pointer-to-a-pointer.
            // Passing `&someLocalPointerVariable` (an actual second level of
            // indirection) makes the kernel copy rusage_info_v4-sized data
            // into that 8-byte stack local instead of the real struct,
            // smashing the stack — this crashed reproducibly until fixed.
            var rusage = rusage_info_v4()
            let rusageResult = withUnsafeMutablePointer(to: &rusage) { structPtr -> Int32 in
                structPtr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPtr in
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, reboundPtr)
                }
            }
            let diskRead = rusageResult == 0 ? rusage.ri_diskio_bytesread : 0
            let diskWrite = rusageResult == 0 ? rusage.ri_diskio_byteswritten : 0

            var cpuPercent = 0.0
            var readPerSec = 0.0
            var writePerSec = 0.0
            if let prev = previous[pid] {
                let elapsed = elapsedSeconds(from: prev.timestamp, to: now)
                if elapsed > 0 {
                    let ticksDelta = totalNanoseconds >= prev.cpuTicksNanoseconds
                        ? totalNanoseconds - prev.cpuTicksNanoseconds : 0
                    cpuPercent = (Double(ticksDelta) / 1_000_000_000.0) / elapsed * 100.0
                    if diskRead >= prev.diskRead {
                        readPerSec = Double(diskRead - prev.diskRead) / elapsed
                    }
                    if diskWrite >= prev.diskWrite {
                        writePerSec = Double(diskWrite - prev.diskWrite) / elapsed
                    }
                }
            }
            previous[pid] = PrevStats(
                cpuTicksNanoseconds: totalNanoseconds,
                diskRead: diskRead,
                diskWrite: diskWrite,
                timestamp: now
            )

            results.append(
                ProcessSnapshot(
                    pid: pid,
                    name: Self.name(for: pid),
                    cpuUsagePercent: cpuPercent,
                    residentMemoryBytes: taskInfo.pti_resident_size,
                    diskBytesReadPerSec: readPerSec,
                    diskBytesWrittenPerSec: writePerSec
                )
            )
        }

        previous = previous.filter { stillAlive.contains($0.key) }
        return results
    }

    private func elapsedSeconds(from start: ContinuousClock.Instant, to end: ContinuousClock.Instant) -> Double {
        let duration = end - start
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    private static func name(for pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 64)
        let length = buffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
            proc_name(pid, ptr.baseAddress, UInt32(ptr.count))
        }
        guard length > 0 else { return "pid \(pid)" }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func listPIDs() -> [pid_t] {
        let size = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard size > 0 else { return [] }
        let capacity = Int(size) / MemoryLayout<pid_t>.size + 16
        var pids = [pid_t](repeating: 0, count: capacity)
        let bytesWritten = pids.withUnsafeMutableBufferPointer { ptr -> Int32 in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, ptr.baseAddress, Int32(ptr.count * MemoryLayout<pid_t>.size))
        }
        guard bytesWritten > 0 else { return [] }
        let count = Int(bytesWritten) / MemoryLayout<pid_t>.size
        return Array(pids.prefix(count)).filter { $0 != 0 }
    }
}
