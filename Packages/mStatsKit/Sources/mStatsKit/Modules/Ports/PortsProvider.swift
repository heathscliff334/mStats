import Foundation
import CSystemShims

/// Enumerates locally listening TCP/UDP ports by shelling out to `lsof`
/// (this app runs unsandboxed, so shelling out is available, and there is no
/// single syscall that both lists listening sockets and resolves the owning
/// process name/PID). `lsof`'s COMMAND column truncates process names, so
/// each PID's full name is re-resolved via `proc_name` (libproc) same as
/// ProcessSnapshotProvider does, for a nicer display name. Kill signals go
/// through the `kill(2)` syscall directly (not `/bin/kill`) so errno can be
/// inspected and surfaced to the UI instead of assumed.
public actor PortsProvider: SystemMetricProvider {
    public init() {}

    public func poll() async -> PortsSnapshot {
        let tcpOutput = Self.runLsof(arguments: ["-iTCP", "-sTCP:LISTEN", "-n", "-P"])
        let udpOutput = Self.runLsof(arguments: ["-iUDP", "-n", "-P"])

        var entries = PortsParser.parse(lsofOutput: tcpOutput, protocolOverride: .tcp)
            + PortsParser.parse(lsofOutput: udpOutput, protocolOverride: .udp)
        entries = PortsParser.deduplicate(entries)

        entries = entries.map { entry in
            guard let resolved = Self.resolvedProcessName(pid: entry.pid), !resolved.isEmpty else { return entry }
            return PortEntry(port: entry.port, protocolKind: entry.protocolKind, processName: resolved, pid: entry.pid, address: entry.address)
        }

        return PortsSnapshot(entries: entries.sorted { $0.port < $1.port })
    }

    public enum SignalResult: Sendable, Equatable {
        case success
        case permissionDenied
        case noSuchProcess
        case failed(Int32)
    }

    /// Sends `signalNumber` to `pid` via the raw Darwin `kill(2)` syscall.
    /// Never escalates privileges — a process owned by another user simply
    /// reports `.permissionDenied` (EPERM), surfaced verbatim to the UI.
    public nonisolated func sendSignal(pid: Int32, signalNumber: Int32) -> SignalResult {
        let result = kill(pid_t(pid), signalNumber)
        if result == 0 { return .success }
        switch errno {
        case EPERM: return .permissionDenied
        case ESRCH: return .noSuchProcess
        default: return .failed(errno)
        }
    }

    private static func runLsof(arguments: [String]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = arguments
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return ""
        }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func resolvedProcessName(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 64)
        let length = buffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
            proc_name(pid, ptr.baseAddress, UInt32(ptr.count))
        }
        guard length > 0 else { return nil }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
