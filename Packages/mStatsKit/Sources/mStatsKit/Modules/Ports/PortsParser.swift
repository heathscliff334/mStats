import Foundation

/// Pure parser for `lsof -i ...` textual output, extracted so it's testable
/// against fixture text without actually shelling out. Column layout:
/// `COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME` — NODE is the
/// protocol (TCP/UDP), NAME is "host:port" (optionally "(LISTEN)" for TCP,
/// or "local->remote" for an established UDP flow, which is filtered out
/// since that's not a listening port).
enum PortsParser {
    static func parse(lsofOutput: String, protocolOverride: PortProtocolKind) -> [PortEntry] {
        var results: [PortEntry] = []
        let lines = lsofOutput.split(separator: "\n", omittingEmptySubsequences: true)

        for line in lines {
            let tokens = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard tokens.count >= 9, tokens[0] != "COMMAND" else { continue }
            guard let pid = Int32(tokens[1]) else { continue }

            let nameField = tokens[8]
            guard !nameField.contains("->") else { continue } // established flow, not a listener

            guard let colonIndex = nameField.lastIndex(of: ":") else { continue }
            let addressPart = String(nameField[nameField.startIndex..<colonIndex])
            let portPart = nameField[nameField.index(after: colonIndex)...]
            guard let port = Int(portPart) else { continue } // e.g. "*:*" wildcard, not a bound port

            let protocolKind = PortProtocolKind(rawValue: tokens[7].uppercased()) ?? protocolOverride

            results.append(PortEntry(
                port: port,
                protocolKind: protocolKind,
                processName: tokens[0],
                pid: pid,
                address: addressPart.isEmpty ? "*" : addressPart
            ))
        }
        return results
    }

    /// Removes exact (pid, protocol, port) duplicates lsof can emit twice
    /// (e.g. one row per IPv4 and IPv6 socket bound to the same port). A
    /// process listening on genuinely different ports keeps one row each.
    static func deduplicate(_ entries: [PortEntry]) -> [PortEntry] {
        var seen = Set<String>()
        var result: [PortEntry] = []
        for entry in entries {
            let key = "\(entry.pid)-\(entry.protocolKind.rawValue)-\(entry.port)"
            if seen.insert(key).inserted {
                result.append(entry)
            }
        }
        return result
    }
}
