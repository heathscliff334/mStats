import Testing
@testable import mStatsKit

@Suite struct CPUProviderTests {
    @Test func fullyIdleCoreReportsAllIdle() {
        let previous = [CoreTicks(user: 0, system: 0, idle: 0, nice: 0)]
        let current = [CoreTicks(user: 0, system: 0, idle: 1000, nice: 0)]
        let result = CPUTickMath.percentages(previous: previous, current: current, efficiencyCoreCount: nil)
        #expect(result.idlePercent == 100)
        #expect(result.userPercent == 0)
        #expect(result.systemPercent == 0)
    }

    @Test func mixedUserSystemIdleSumsToHundred() {
        let previous = [CoreTicks(user: 0, system: 0, idle: 0, nice: 0)]
        let current = [CoreTicks(user: 50, system: 30, idle: 20, nice: 0)]
        let result = CPUTickMath.percentages(previous: previous, current: current, efficiencyCoreCount: nil)
        #expect(result.userPercent == 50)
        #expect(result.systemPercent == 30)
        #expect(result.idlePercent == 20)
    }

    @Test func efficiencyPerformanceSplitByCoreIndex() {
        // 2 efficiency cores (fully busy), 1 performance core (fully idle).
        let previous = Array(repeating: CoreTicks(user: 0, system: 0, idle: 0, nice: 0), count: 3)
        let current = [
            CoreTicks(user: 100, system: 0, idle: 0, nice: 0),
            CoreTicks(user: 100, system: 0, idle: 0, nice: 0),
            CoreTicks(user: 0, system: 0, idle: 100, nice: 0)
        ]
        let result = CPUTickMath.percentages(previous: previous, current: current, efficiencyCoreCount: 2)
        #expect(result.efficiencyCorePercent == 100)
        #expect(result.performanceCorePercent == 0)
    }

    @Test func noPerfLevelSplitWhenCoreCountUnknown() {
        let previous = [CoreTicks(user: 0, system: 0, idle: 0, nice: 0)]
        let current = [CoreTicks(user: 10, system: 0, idle: 90, nice: 0)]
        let result = CPUTickMath.percentages(previous: previous, current: current, efficiencyCoreCount: nil)
        #expect(result.efficiencyCorePercent == nil)
        #expect(result.performanceCorePercent == nil)
    }

    @Test func mismatchedCoreCountsFallBackToEmpty() {
        let previous = [CoreTicks(user: 0, system: 0, idle: 0, nice: 0)]
        let current = [
            CoreTicks(user: 10, system: 0, idle: 90, nice: 0),
            CoreTicks(user: 10, system: 0, idle: 90, nice: 0)
        ]
        let result = CPUTickMath.percentages(previous: previous, current: current, efficiencyCoreCount: nil)
        #expect(result.idlePercent == 100)
    }

    @Test func counterWraparoundIsClampedNotNegative() {
        // Simulates a 32-bit tick counter wrapping around between polls.
        let previous = [CoreTicks(user: .max - 5, system: 0, idle: 0, nice: 0)]
        let current = [CoreTicks(user: 10, system: 0, idle: 0, nice: 0)]
        let result = CPUTickMath.percentages(previous: previous, current: current, efficiencyCoreCount: nil)
        #expect(result.userPercent >= 0)
    }
}
