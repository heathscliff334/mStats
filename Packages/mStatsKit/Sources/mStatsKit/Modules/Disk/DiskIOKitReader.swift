import Foundation
import IOKit

/// Walks the IOKit registry tree for every `IOBlockStorageDriver`-conforming
/// service and sums its cumulative read/write byte counters. On Apple
/// Silicon internal storage this class hierarchy differs from classic Intel
/// setups, so this is validated empirically at runtime rather than assumed
/// — if no matching services are found, callers see all-zero throughput
/// rather than a crash.
public struct DiskIOKitReader: Sendable {
    public init() {}

    public func cumulativeBytes() -> (read: UInt64, write: UInt64) {
        var iterator: io_iterator_t = 0
        let matchResult = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOBlockStorageDriver"),
            &iterator
        )
        guard matchResult == KERN_SUCCESS else { return (0, 0) }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }

            var propertiesUnmanaged: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propertiesUnmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let propertiesUnmanaged else { continue }
            let properties = propertiesUnmanaged.takeRetainedValue() as? [String: Any] ?? [:]
            guard let stats = properties["Statistics"] as? [String: Any] else { continue }

            if let read = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value {
                totalRead += read
            }
            if let write = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value {
                totalWrite += write
            }
        }
        return (totalRead, totalWrite)
    }
}
