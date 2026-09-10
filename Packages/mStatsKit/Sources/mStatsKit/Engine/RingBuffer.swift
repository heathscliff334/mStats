import Foundation

/// Fixed-capacity FIFO sample buffer backing every sparkline. Appending past
/// capacity drops the oldest sample in O(1) rather than growing unbounded.
public struct RingBuffer<Element>: Sendable where Element: Sendable {
    public let capacity: Int
    private var storage: [Element] = []

    public init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be positive")
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    public mutating func append(_ element: Element) {
        storage.append(element)
        if storage.count > capacity {
            storage.removeFirst(storage.count - capacity)
        }
    }

    public var values: [Element] { storage }
    public var isEmpty: Bool { storage.isEmpty }
    public var count: Int { storage.count }
    public var last: Element? { storage.last }
}
