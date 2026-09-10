import Foundation
import Observation
import Darwin
import os

/// Ports needs its own hand-rolled view model (not the generic
/// `ModuleViewModel<Provider>`) because, unlike every read-only module, it
/// also performs user-triggered actions (stop/force-kill) that must refresh
/// the list immediately afterward rather than waiting for the next poll tick.
@Observable
@MainActor
public final class PortsViewModel {
    public private(set) var snapshot: PortsSnapshot = .empty
    public private(set) var lastActionError: String?

    private let provider = PortsProvider()
    private let settings: AppSettings
    private let logger = MetricLog.logger("Ports")
    private nonisolated(unsafe) var pollTask: Task<Void, Never>?

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshNow()
                try? await Task.sleep(for: .seconds(max(1, self.settings.portsPollInterval)))
            }
        }
    }

    public func refreshNow() async {
        let snap = await provider.poll()
        self.snapshot = snap
        if MetricLog.debugStdout {
            print("[Ports] \(snap.entries.count) listening ports")
        }
        logger.debug("\(snap.entries.count, privacy: .public) listening ports")
    }

    /// Graceful stop (SIGTERM). Caller (the card view) is responsible for
    /// confirming with the user first — this executes unconditionally.
    public func stop(entry: PortEntry) async {
        await performAction(pid: entry.pid, signalNumber: SIGTERM)
    }

    /// Force kill (SIGKILL). Caller is responsible for confirming with the
    /// user first — this executes unconditionally.
    public func forceKill(entry: PortEntry) async {
        await performAction(pid: entry.pid, signalNumber: SIGKILL)
    }

    private func performAction(pid: Int32, signalNumber: Int32) async {
        lastActionError = nil
        switch provider.sendSignal(pid: pid, signalNumber: signalNumber) {
        case .success:
            break
        case .permissionDenied:
            lastActionError = "Permission denied — that process is owned by another user"
        case .noSuchProcess:
            lastActionError = "That process no longer exists"
        case .failed(let code):
            lastActionError = "Failed to signal process (errno \(code))"
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
