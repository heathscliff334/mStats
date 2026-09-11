import Foundation

public struct ContainerEntry: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let image: String
    public let status: String
    public let cpuPercentText: String?
    public let memoryUsageText: String?

    public var isRunning: Bool { status.localizedCaseInsensitiveContains("Up") }

    public init(id: String, name: String, image: String, status: String, cpuPercentText: String?, memoryUsageText: String?) {
        self.id = id
        self.name = name
        self.image = image
        self.status = status
        self.cpuPercentText = cpuPercentText
        self.memoryUsageText = memoryUsageText
    }
}

public struct DockerSnapshot: Sendable {
    /// Whether the Docker daemon is currently reachable at all — drives
    /// whether the menu bar icon should exist (see DockerViewModel).
    public let isRunning: Bool
    public let containers: [ContainerEntry]

    public static let notRunning = DockerSnapshot(isRunning: false, containers: [])

    public init(isRunning: Bool, containers: [ContainerEntry]) {
        self.isRunning = isRunning
        self.containers = containers
    }
}
