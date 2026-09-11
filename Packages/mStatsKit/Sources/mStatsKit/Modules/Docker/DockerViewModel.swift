import Foundation
import Observation

/// Hand-rolled (not the generic `ModuleViewModel`) for the same reason as
/// Ports: it performs user-triggered actions that must refresh immediately,
/// plus it tracks `isRunning` separately from `snapshot` so the app
/// delegate can decide whether to show a menu bar icon at all — detection
/// and stats collection happen together in one poll (see DockerProvider).
@Observable
@MainActor
public final class DockerViewModel {
    public private(set) var snapshot: DockerSnapshot = .notRunning
    public private(set) var lastActionError: String?

    public var isRunning: Bool { snapshot.isRunning }

    private let provider = DockerProvider()
    private let settings: AppSettings
    private let logger = MetricLog.logger("Docker")
    private nonisolated(unsafe) var pollTask: Task<Void, Never>?

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshNow()
                try? await Task.sleep(for: .seconds(max(3, self.settings.dockerPollInterval)))
            }
        }
    }

    public func refreshNow() async {
        let snap = await provider.poll()
        self.snapshot = snap
        if MetricLog.debugStdout {
            print("[Docker] running=\(snap.isRunning) containers=\(snap.containers.count)")
        }
        logger.debug("running=\(snap.isRunning, privacy: .public) containers=\(snap.containers.count, privacy: .public)")
    }

    public func start(container: ContainerEntry) async {
        await performAction { await provider.start(containerID: container.id) }
    }

    public func stop(container: ContainerEntry) async {
        await performAction { await provider.stop(containerID: container.id) }
    }

    public func restart(container: ContainerEntry) async {
        await performAction { await provider.restart(containerID: container.id) }
    }

    private func performAction(_ operation: () async -> DockerProvider.ActionResult) async {
        lastActionError = nil
        switch await operation() {
        case .success:
            break
        case .failed(let message):
            lastActionError = message
        }
        await refreshNow()
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    deinit {
        pollTask?.cancel()
    }
}
