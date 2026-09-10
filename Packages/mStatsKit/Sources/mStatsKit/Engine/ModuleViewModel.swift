import Foundation
import Observation
import os

/// Generic polling loop shared by every module. Each module's view model
/// specializes this with its own `SystemMetricProvider`; the loop itself
/// (start/stop, interval lookup, snapshot publishing, debug logging) is
/// written exactly once here.
@Observable
@MainActor
public final class ModuleViewModel<Provider: SystemMetricProvider> {
    public private(set) var snapshot: Provider.Snapshot?
    public let provider: Provider

    private let category: String
    private let logger: Logger
    private let pollInterval: () -> TimeInterval
    // Task.cancel() is safe to call from any thread; nonisolated(unsafe) lets
    // deinit (always nonisolated) cancel it without hopping to MainActor.
    private nonisolated(unsafe) var task: Task<Void, Never>?

    public init(
        provider: Provider,
        category: String,
        pollInterval: @escaping () -> TimeInterval
    ) {
        self.provider = provider
        self.category = category
        self.logger = MetricLog.logger(category)
        self.pollInterval = pollInterval
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let snap = await self.provider.poll()
                self.snapshot = snap
                if MetricLog.debugStdout {
                    print("[\(self.category)] \(String(describing: snap))")
                }
                self.logger.debug("\(String(describing: snap), privacy: .public)")
                let interval = max(0.25, self.pollInterval())
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
