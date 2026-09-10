import Foundation
import Network

/// Wraps NWPathMonitor (official, stable API) to answer "what kind of
/// connection is active right now" for a poll-based model — the monitor
/// itself is callback-driven, so this keeps the last-reported type cached.
public final class NetworkPathObserver: @unchecked Sendable {
    public static let shared = NetworkPathObserver()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var _type: NetworkConnectionType = .unavailable

    public var currentType: NetworkConnectionType {
        lock.lock()
        defer { lock.unlock() }
        return _type
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let type: NetworkConnectionType
            if path.status != .satisfied {
                type = .unavailable
            } else if path.usesInterfaceType(.wifi) {
                type = .wifi
            } else if path.usesInterfaceType(.wiredEthernet) {
                type = .wired
            } else if path.usesInterfaceType(.cellular) {
                type = .cellular
            } else {
                type = .other
            }
            self.lock.lock()
            self._type = type
            self.lock.unlock()
        }
        monitor.start(queue: DispatchQueue(label: "com.hartono.mStats.pathmonitor"))
    }
}
