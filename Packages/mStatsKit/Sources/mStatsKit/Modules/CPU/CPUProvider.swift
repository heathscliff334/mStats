import Foundation
import Darwin

/// Reads per-core CPU tick counters from `host_processor_info`, diffing
/// against the previous poll for instantaneous percentages (delta math
/// lives in `CPUTickMath`, tested separately against fixture data).
/// Efficiency vs. Performance core split (Apple Silicon only) comes from
/// `hw.perflevel{0,1}.physicalcpu`; on Intel `hw.nperflevels` is absent and
/// the split is reported as unavailable rather than guessed.
public actor CPUProvider: SystemMetricProvider {
    private struct PerfLevels {
        let performanceCoreCount: Int
        let efficiencyCoreCount: Int
    }

    private var previousTicks: [CoreTicks] = []
    private let perfLevels: PerfLevels?

    public init() {
        perfLevels = Self.readPerfLevels()
    }

    public func poll() async -> CPUSnapshot {
        guard let ticks = Self.readCoreTicks() else { return .empty }

        let percentages = CPUTickMath.percentages(
            previous: previousTicks,
            current: ticks,
            efficiencyCoreCount: perfLevels?.efficiencyCoreCount
        )
        previousTicks = ticks

        let topProcesses = await ProcessSnapshotProvider.shared
            .currentSnapshots(minimumInterval: 1.0)
            .sorted { $0.cpuUsagePercent > $1.cpuUsagePercent }
            .prefix(5)

        return CPUSnapshot(
            userPercent: percentages.userPercent,
            systemPercent: percentages.systemPercent,
            idlePercent: percentages.idlePercent,
            efficiencyCorePercent: percentages.efficiencyCorePercent,
            performanceCorePercent: percentages.performanceCorePercent,
            topProcesses: Array(topProcesses)
        )
    }

    private static func readCoreTicks() -> [CoreTicks]? {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUsU,
            &cpuInfo,
            &numCpuInfo
        )
        guard result == KERN_SUCCESS, let cpuInfo else { return nil }
        defer {
            let size = vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: cpuInfo)), size)
        }

        var ticks: [CoreTicks] = []
        ticks.reserveCapacity(Int(numCPUsU))
        for i in 0..<Int(numCPUsU) {
            let base = i * Int(CPU_STATE_MAX)
            ticks.append(
                CoreTicks(
                    user: UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_USER)]),
                    system: UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_SYSTEM)]),
                    idle: UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_IDLE)]),
                    nice: UInt32(bitPattern: cpuInfo[base + Int(CPU_STATE_NICE)])
                )
            )
        }
        return ticks
    }

    private static func readPerfLevels() -> PerfLevels? {
        var nPerfLevels: Int32 = 0
        var levelSize = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.nperflevels", &nPerfLevels, &levelSize, nil, 0) == 0, nPerfLevels >= 2 else {
            return nil
        }
        var performance: Int32 = 0
        var efficiency: Int32 = 0
        var s1 = MemoryLayout<Int32>.size
        var s2 = MemoryLayout<Int32>.size
        guard sysctlbyname("hw.perflevel0.physicalcpu", &performance, &s1, nil, 0) == 0,
              sysctlbyname("hw.perflevel1.physicalcpu", &efficiency, &s2, nil, 0) == 0 else {
            return nil
        }
        return PerfLevels(performanceCoreCount: Int(performance), efficiencyCoreCount: Int(efficiency))
    }
}
