import Foundation
import os

/// A single metric source (CPU, Memory, Disk, ...). Providers are stateless
/// value types where possible; any stateful diffing (previous tick counts,
/// previous byte counters) lives inside the provider instance itself so each
/// module view model owns exactly one long-lived provider.
public protocol SystemMetricProvider: Sendable {
    associatedtype Snapshot: Sendable
    /// Reads current system state and returns a snapshot. Must never throw
    /// for a transient/unsupported reading — represent that inside `Snapshot`
    /// (e.g. an `.unavailable` case) so the UI can degrade gracefully instead
    /// of the whole module going dark on one bad poll.
    func poll() async -> Snapshot
}

public enum MetricLog {
    public static let subsystem = "com.hartono.mStats"

    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }

    /// When true, providers additionally print each poll to stdout so a
    /// headless run (no Console.app) can be inspected directly.
    public static let debugStdout: Bool = {
        ProcessInfo.processInfo.environment["MSTATS_DEBUG_LOG"] == "1"
    }()
}
