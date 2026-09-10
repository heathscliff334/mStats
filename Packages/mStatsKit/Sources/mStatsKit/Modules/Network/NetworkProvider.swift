import Foundation
import Darwin

/// Byte counters and local IPs come from `getifaddrs`/`if_data`, summed
/// across "en*" hardware interfaces (Wi-Fi/Ethernet) only — deliberately
/// excludes loopback and virtual/tunnel interfaces so throughput matches
/// what a user would recognize as "my network activity". Note: `if_data`'s
/// counters are 32-bit and wrap at 4GB cumulative; acceptable for a
/// derived per-second rate but a known limitation of this classic API
/// (the 64-bit variant requires an ioctl this provider doesn't use yet).
public actor NetworkProvider: SystemMetricProvider {
    private var previousBytes: (rx: UInt64, tx: UInt64)?
    private var previousTimestamp: ContinuousClock.Instant?
    private var peakDownload: Double = 0
    private var peakUpload: Double = 0

    public init() {}

    public func poll() async -> NetworkSnapshot {
        let (rx, tx, localIPs) = Self.readInterfaces()
        let now = ContinuousClock.now

        var download = 0.0
        var upload = 0.0
        if let prev = previousBytes, let prevTime = previousTimestamp {
            let duration = now - prevTime
            let elapsed = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
            if elapsed > 0 {
                if rx >= prev.rx { download = Double(rx - prev.rx) / elapsed }
                if tx >= prev.tx { upload = Double(tx - prev.tx) / elapsed }
            }
        }
        previousBytes = (rx, tx)
        previousTimestamp = now
        peakDownload = max(peakDownload, download)
        peakUpload = max(peakUpload, upload)

        return NetworkSnapshot(
            downloadBytesPerSec: download,
            uploadBytesPerSec: upload,
            peakDownloadBytesPerSec: peakDownload,
            peakUploadBytesPerSec: peakUpload,
            localIPAddresses: localIPs,
            connectionType: NetworkPathObserver.shared.currentType,
            publicIPAddress: nil
        )
    }

    private static func readInterfaces() -> (rx: UInt64, tx: UInt64, localIPs: [String]) {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return (0, 0, []) }
        defer { freeifaddrs(ifaddrPtr) }

        var totalRx: UInt64 = 0
        var totalTx: UInt64 = 0
        var ips: [String] = []

        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = pointer {
            let interface = current.pointee
            pointer = interface.ifa_next

            let name = String(cString: interface.ifa_name)
            guard name.hasPrefix("en"), (Int32(interface.ifa_flags) & IFF_UP) != 0 else { continue }
            guard let sockaddrPtr = interface.ifa_addr else { continue }
            let family = sockaddrPtr.pointee.sa_family

            if family == UInt8(AF_LINK), let dataPtr = interface.ifa_data {
                let networkData = dataPtr.withMemoryRebound(to: if_data.self, capacity: 1) { $0.pointee }
                totalRx += UInt64(networkData.ifi_ibytes)
                totalTx += UInt64(networkData.ifi_obytes)
            } else if family == UInt8(AF_INET) {
                var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    sockaddrPtr,
                    socklen_t(sockaddrPtr.pointee.sa_len),
                    &hostBuffer,
                    socklen_t(hostBuffer.count),
                    nil, 0,
                    NI_NUMERICHOST
                )
                if result == 0 {
                    let bytes = hostBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                    ips.append(String(decoding: bytes, as: UTF8.self))
                }
            }
        }
        return (totalRx, totalTx, ips)
    }
}
