import Testing
@testable import mStatsKit

@Suite struct RingBufferTests {
    @Test func appendWithinCapacityKeepsAllValues() {
        var buffer = RingBuffer<Int>(capacity: 3)
        buffer.append(1)
        buffer.append(2)
        #expect(buffer.values == [1, 2])
    }

    @Test func appendPastCapacityDropsOldest() {
        var buffer = RingBuffer<Int>(capacity: 3)
        for value in 1...5 {
            buffer.append(value)
        }
        #expect(buffer.values == [3, 4, 5])
        #expect(buffer.count == 3)
    }

    @Test func emptyBufferReportsNoLast() {
        let buffer = RingBuffer<Double>(capacity: 5)
        #expect(buffer.isEmpty)
        #expect(buffer.last == nil)
    }

    @Test func lastReflectsMostRecentAppend() {
        var buffer = RingBuffer<Int>(capacity: 2)
        buffer.append(10)
        buffer.append(20)
        buffer.append(30)
        #expect(buffer.last == 30)
    }
}
