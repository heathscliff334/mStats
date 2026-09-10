import Foundation
import Observation
import os

@Observable
@MainActor
public final class DiskViewModel {
    public private(set) var snapshot: DiskSnapshot = .empty
    public private(set) var readHistory = RingBuffer<Double>(capacity: 60)
    public private(set) var writeHistory = RingBuffer<Double>(capacity: 60)

    private let provider = DiskProvider()
    private let settings: AppSettings
    private let logger = MetricLog.logger("Disk")
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
                self.readHistory.append(snap.readBytesPerSec)
                self.writeHistory.append(snap.writeBytesPerSec)
                if MetricLog.debugStdout {
                    let usedPercentText = snap.primaryVolumeUsedPercent.map { String(format: "%.1f%%", $0) } ?? "n/a"
                    print("[Disk] read=\(Formatting.bytes(UInt64(snap.readBytesPerSec)))/s write=\(Formatting.bytes(UInt64(snap.writeBytesPerSec)))/s volumes=\(snap.volumes.count) usedPercent=\(usedPercentText)")
                }
                self.logger.debug("read=\(snap.readBytesPerSec, privacy: .public) write=\(snap.writeBytesPerSec, privacy: .public)")
                try? await Task.sleep(for: .seconds(max(0.25, self.settings.diskPollInterval)))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}
