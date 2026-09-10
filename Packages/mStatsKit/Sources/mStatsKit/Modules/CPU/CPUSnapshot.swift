import Foundation

public struct CPUSnapshot: Sendable {
    public let userPercent: Double
    public let systemPercent: Double
    public let idlePercent: Double
    /// nil on Intel (no perf-level split exists there).
    public let efficiencyCorePercent: Double?
    public let performanceCorePercent: Double?
    public let topProcesses: [ProcessSnapshot]

    public static let empty = CPUSnapshot(
        userPercent: 0, systemPercent: 0, idlePercent: 100,
        efficiencyCorePercent: nil, performanceCorePercent: nil, topProcesses: []
    )
}
