import Testing
@testable import mStatsKit

@Suite struct PortsParserTests {
    @Test func parsesBasicTCPListener() {
        let output = """
        COMMAND     PID  USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        node      12345 kevin   23u  IPv4 0x824158853700852e      0t0  TCP *:3000 (LISTEN)
        """
        let entries = PortsParser.parse(lsofOutput: output, protocolOverride: .tcp)
        #expect(entries.count == 1)
        #expect(entries[0].port == 3000)
        #expect(entries[0].pid == 12345)
        #expect(entries[0].processName == "node")
        #expect(entries[0].protocolKind == .tcp)
        #expect(entries[0].address == "*")
        #expect(entries[0].isDevPort == true)
    }

    @Test func parsesUDPListenerWithoutStateSuffix() {
        let output = """
        COMMAND     PID  USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        sharingd    493 kevin   11u  IPv6  0x10cf99cf84a312d      0t0  UDP *:58215
        """
        let entries = PortsParser.parse(lsofOutput: output, protocolOverride: .udp)
        #expect(entries.count == 1)
        #expect(entries[0].port == 58215)
        #expect(entries[0].protocolKind == .udp)
        #expect(entries[0].isDevPort == false)
    }

    @Test func skipsWildcardUDPEntriesWithNoBoundPort() {
        let output = """
        COMMAND     PID  USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        identitys   491 kevin    7u  IPv4 0x2154578530ec7346      0t0  UDP *:*
        """
        let entries = PortsParser.parse(lsofOutput: output, protocolOverride: .udp)
        #expect(entries.isEmpty)
    }

    @Test func skipsEstablishedUDPFlowsNotListeners() {
        let output = """
        COMMAND     PID  USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        Google     1285 kevin   19u  IPv4 0x71103105043b488e      0t0  UDP 192.168.0.183:61586->74.125.130.138:443
        """
        let entries = PortsParser.parse(lsofOutput: output, protocolOverride: .udp)
        #expect(entries.isEmpty)
    }

    @Test func honorsExplicitProtocolColumnOverOverride() {
        let output = """
        COMMAND     PID  USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        Postgres    111 kevin    7u  IPv4 0x1111111111111        0t0  TCP 127.0.0.1:5432 (LISTEN)
        """
        // Even if called with the "wrong" override, the NODE column (TCP) wins.
        let entries = PortsParser.parse(lsofOutput: output, protocolOverride: .udp)
        #expect(entries.count == 1)
        #expect(entries[0].protocolKind == .tcp)
        #expect(entries[0].address == "127.0.0.1")
    }

    @Test func deduplicatesSamePidProtocolPortAcrossIPv4AndIPv6() {
        let output = """
        COMMAND     PID  USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        rapportd    457 kevin   10u  IPv4 0x824158853700852e      0t0  TCP *:64863 (LISTEN)
        rapportd    457 kevin   11u  IPv6 0xef6fb96460b559f9      0t0  TCP *:64863 (LISTEN)
        """
        let parsed = PortsParser.parse(lsofOutput: output, protocolOverride: .tcp)
        #expect(parsed.count == 2)
        let deduped = PortsParser.deduplicate(parsed)
        #expect(deduped.count == 1)
        #expect(deduped[0].port == 64863)
    }

    @Test func keepsDistinctPortsForSamePid() {
        let output = """
        COMMAND     PID  USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        ControlCe   539 kevin    9u  IPv4 0xa4e1aa7e0295d6b4      0t0  TCP *:7000 (LISTEN)
        ControlCe   539 kevin   11u  IPv4 0xe6cc5ef0e887a3a8      0t0  TCP *:5000 (LISTEN)
        """
        let parsed = PortsParser.deduplicate(PortsParser.parse(lsofOutput: output, protocolOverride: .tcp))
        #expect(parsed.count == 2)
        #expect(Set(parsed.map(\.port)) == [7000, 5000])
    }

    @Test func ignoresHeaderRow() {
        let output = "COMMAND     PID  USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME"
        let entries = PortsParser.parse(lsofOutput: output, protocolOverride: .tcp)
        #expect(entries.isEmpty)
    }
}
