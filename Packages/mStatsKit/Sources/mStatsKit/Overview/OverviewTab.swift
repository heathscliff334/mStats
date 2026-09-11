import Foundation

/// One tab in the combined overview panel — mirrors the 7 modules in a
/// fixed, stable order.
public enum OverviewTab: String, CaseIterable, Identifiable, Sendable {
    case cpu, memory, disk, network, sensors, battery, ports, docker, clipboard

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .network: return "Network"
        case .sensors: return "Sensors & Fans"
        case .battery: return "Battery"
        case .ports: return "Ports"
        case .docker: return "Docker"
        case .clipboard: return "Clipboard"
        }
    }

    public var systemImage: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .sensors: return "thermometer.medium"
        case .battery: return "battery.100"
        case .ports: return "point.3.connected.trianglepath.dotted"
        case .docker: return "shippingbox"
        case .clipboard: return "doc.on.clipboard"
        }
    }

    /// Pure derivation of which tabs should appear, in fixed order — kept
    /// free of `AppSettings` so it's trivially testable with plain Bools.
    /// `docker` additionally requires live detection (`dockerRunning`), not
    /// just its enabled flag — same rule as its standalone menu bar icon.
    public static func enabledTabs(
        cpu: Bool,
        memory: Bool,
        disk: Bool,
        network: Bool,
        sensors: Bool,
        battery: Bool,
        ports: Bool,
        docker: Bool,
        dockerRunning: Bool,
        clipboard: Bool
    ) -> [OverviewTab] {
        var tabs: [OverviewTab] = []
        if cpu { tabs.append(.cpu) }
        if memory { tabs.append(.memory) }
        if disk { tabs.append(.disk) }
        if network { tabs.append(.network) }
        if sensors { tabs.append(.sensors) }
        if battery { tabs.append(.battery) }
        if ports { tabs.append(.ports) }
        if docker && dockerRunning { tabs.append(.docker) }
        if clipboard { tabs.append(.clipboard) }
        return tabs
    }

    /// The tab that should be selected: `preferred` if it's still enabled,
    /// otherwise the first enabled tab, otherwise nil (nothing enabled).
    public static func resolveSelection(preferred: OverviewTab?, enabled: [OverviewTab]) -> OverviewTab? {
        if let preferred, enabled.contains(preferred) { return preferred }
        return enabled.first
    }
}
