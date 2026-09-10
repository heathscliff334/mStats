import Foundation
import Observation
import os

@Observable
@MainActor
public final class CPUViewModel {
    public private(set) var snapshot: CPUSnapshot = .empty
    public private(set) var userHistory = RingBuffer<Double>(capacity: 60)
    public private(set) var systemHistory = RingBuffer<Double>(capacity: 60)

    private let provider = CPUProvider()
    private let settings: AppSettings
    private let logger = MetricLog.logger("CPU")
    private nonisolated(unsafe) var task: Task<Void, Never>?

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let snap = await self.provider.poll()
                self.snapshot = snap
                self.userHistory.append(snap.userPercent)
                self.systemHistory.append(snap.systemPercent)
                if MetricLog.debugStdout {
                    print("[CPU] user=\(String(format: "%.1f", snap.userPercent))% system=\(String(format: "%.1f", snap.systemPercent))% eff=\(snap.efficiencyCorePercent.map { String(format: "%.0f%%", $0) } ?? "n/a") perf=\(snap.performanceCorePercent.map { String(format: "%.0f%%", $0) } ?? "n/a")")
                }
                self.logger.debug("user=\(snap.userPercent, privacy: .public) system=\(snap.systemPercent, privacy: .public)")
                try? await Task.sleep(for: .seconds(max(0.25, self.settings.cpuPollInterval)))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}
