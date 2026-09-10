import Foundation
import Observation
import os

@Observable
@MainActor
public final class NetworkViewModel {
    public private(set) var snapshot: NetworkSnapshot = .empty
    public private(set) var downloadHistory = RingBuffer<Double>(capacity: 60)
    public private(set) var uploadHistory = RingBuffer<Double>(capacity: 60)
    public private(set) var publicIPAddress: String?

    private let provider = NetworkProvider()
    private let publicIPFetcher = PublicIPFetcher()
    private let settings: AppSettings
    private let logger = MetricLog.logger("Network")
    private nonisolated(unsafe) var pollTask: Task<Void, Never>?
    private nonisolated(unsafe) var publicIPTask: Task<Void, Never>?

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public func start() {
        startPolling()
        startPublicIPPolling()
    }

    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let snap = await self.provider.poll()
                self.snapshot = snap
                self.downloadHistory.append(snap.downloadBytesPerSec)
                self.uploadHistory.append(snap.uploadBytesPerSec)
                if MetricLog.debugStdout {
                    print("[Network] down=\(Formatting.bytes(UInt64(snap.downloadBytesPerSec)))/s up=\(Formatting.bytes(UInt64(snap.uploadBytesPerSec)))/s type=\(snap.connectionType)")
                }
                self.logger.debug("down=\(snap.downloadBytesPerSec, privacy: .public) up=\(snap.uploadBytesPerSec, privacy: .public)")
                try? await Task.sleep(for: .seconds(max(0.25, self.settings.networkPollInterval)))
            }
        }
    }

    private func startPublicIPPolling() {
        guard publicIPTask == nil else { return }
        publicIPTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if self.settings.publicIPEnabled {
                    let ip = await self.publicIPFetcher.poll()
                    self.publicIPAddress = ip
                    if MetricLog.debugStdout, let ip {
                        print("[Network] publicIP=\(ip)")
                    }
                } else {
                    self.publicIPAddress = nil
                }
                try? await Task.sleep(for: .seconds(max(30, self.settings.publicIPPollInterval)))
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        publicIPTask?.cancel()
        publicIPTask = nil
    }

    deinit {
        pollTask?.cancel()
        publicIPTask?.cancel()
    }
}
