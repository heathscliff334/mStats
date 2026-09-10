import Foundation

/// Pure delta-math extracted from CPUProvider so it's testable with fixture
/// tick data, with no live `host_processor_info` syscall involved.
struct CoreTicks: Sendable, Equatable {
    var user: UInt32
    var system: UInt32
    var idle: UInt32
    var nice: UInt32
}

struct CPUPercentages: Sendable, Equatable {
    var userPercent: Double
    var systemPercent: Double
    var idlePercent: Double
    var efficiencyCorePercent: Double?
    var performanceCorePercent: Double?
}

enum CPUTickMath {
    /// `efficiencyCoreCount` nil means no perf-level split is available
    /// (Intel); cores at index < efficiencyCoreCount are treated as
    /// efficiency cores, the rest as performance cores.
    static func percentages(
        previous: [CoreTicks],
        current: [CoreTicks],
        efficiencyCoreCount: Int?
    ) -> CPUPercentages {
        guard previous.count == current.count, !current.isEmpty else {
            return CPUPercentages(userPercent: 0, systemPercent: 0, idlePercent: 100, efficiencyCorePercent: nil, performanceCorePercent: nil)
        }

        var userSum = 0.0, systemSum = 0.0, idleSum = 0.0
        var validCores = 0
        var efficiencyBusySum = 0.0, efficiencyCoresSeen = 0
        var performanceBusySum = 0.0, performanceCoresSeen = 0

        for index in current.indices {
            let prev = previous[index]
            let cur = current[index]
            let userDelta = Double(cur.user &- prev.user)
            let systemDelta = Double(cur.system &- prev.system)
            let idleDelta = Double(cur.idle &- prev.idle)
            let niceDelta = Double(cur.nice &- prev.nice)
            let total = userDelta + systemDelta + idleDelta + niceDelta
            guard total > 0 else { continue }

            let userPct = (userDelta + niceDelta) / total * 100
            let systemPct = systemDelta / total * 100
            let idlePct = idleDelta / total * 100
            userSum += userPct
            systemSum += systemPct
            idleSum += idlePct
            validCores += 1

            if let efficiencyCoreCount {
                if index < efficiencyCoreCount {
                    efficiencyBusySum += userPct + systemPct
                    efficiencyCoresSeen += 1
                } else {
                    performanceBusySum += userPct + systemPct
                    performanceCoresSeen += 1
                }
            }
        }

        let n = Double(max(validCores, 1))
        return CPUPercentages(
            userPercent: userSum / n,
            systemPercent: systemSum / n,
            idlePercent: validCores > 0 ? idleSum / n : 100,
            efficiencyCorePercent: efficiencyCoresSeen > 0 ? efficiencyBusySum / Double(efficiencyCoresSeen) : nil,
            performanceCorePercent: performanceCoresSeen > 0 ? performanceBusySum / Double(performanceCoresSeen) : nil
        )
    }
}
