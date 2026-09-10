import Testing
@testable import mStatsKit

@Suite struct PortsFilterTests {
    private let node = PortEntry(port: 3000, protocolKind: .tcp, processName: "node", pid: 12345, address: "*")
    private let adb = PortEntry(port: 5037, protocolKind: .tcp, processName: "adb", pid: 24225, address: "127.0.0.1")
    private let postgres = PortEntry(port: 5432, protocolKind: .tcp, processName: "postgres", pid: 111, address: "127.0.0.1")

    @Test func emptyQueryMatchesEverything() {
        #expect(PortsFilter.matches(node, query: ""))
        #expect(PortsFilter.matches(adb, query: "   "))
    }

    @Test func matchesByProcessNameCaseInsensitive() {
        #expect(PortsFilter.matches(adb, query: "ADB"))
        #expect(!PortsFilter.matches(node, query: "ADB"))
    }

    @Test func matchesByPortSubstring() {
        #expect(PortsFilter.matches(adb, query: "5037"))
        #expect(PortsFilter.matches(node, query: "300"))
        #expect(!PortsFilter.matches(node, query: "3001"))
    }

    @Test func noMatchReturnsFalse() {
        #expect(!PortsFilter.matches(postgres, query: "nginx"))
    }
}
