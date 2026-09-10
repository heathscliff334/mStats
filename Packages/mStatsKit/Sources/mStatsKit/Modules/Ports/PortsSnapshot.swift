import Foundation

public enum PortProtocolKind: String, Sendable, CaseIterable {
    case tcp = "TCP"
    case udp = "UDP"
}

/// One locally listening socket. `isDevPort` flags common web-dev framework
/// default ports so a developer's own servers stand out from system noise
/// (rapportd, ControlCenter, etc. also listen on plenty of ports).
public struct PortEntry: Sendable, Hashable, Identifiable {
    public let port: Int
    public let protocolKind: PortProtocolKind
    public let processName: String
    public let pid: Int32
    public let address: String

    public var id: String { "\(pid)-\(protocolKind.rawValue)-\(port)" }

    public var isDevPort: Bool { Self.devPorts.contains(port) }

    static let devPorts: Set<Int> = [3000, 3001, 4200, 5000, 5173, 5174, 8000, 8080, 8081, 9000, 9090]

    public init(port: Int, protocolKind: PortProtocolKind, processName: String, pid: Int32, address: String) {
        self.port = port
        self.protocolKind = protocolKind
        self.processName = processName
        self.pid = pid
        self.address = address
    }
}

public struct PortsSnapshot: Sendable {
    public let entries: [PortEntry]

    public static let empty = PortsSnapshot(entries: [])
}
