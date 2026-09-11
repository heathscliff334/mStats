import Testing
@testable import mStatsKit

@Suite struct DockerParserTests {
    @Test func parsesBasicPSLine() {
        let output = "abc123def456|my-app|nginx:latest|Up 2 hours"
        let entries = DockerParser.parsePS(output)
        #expect(entries.count == 1)
        #expect(entries[0].id == "abc123def456")
        #expect(entries[0].name == "my-app")
        #expect(entries[0].image == "nginx:latest")
        #expect(entries[0].status == "Up 2 hours")
    }

    @Test func parsesMultiplePSLines() {
        let output = """
        abc111|web|nginx|Up 1 hour
        abc222|db|postgres:15|Exited (0) 3 minutes ago
        """
        let entries = DockerParser.parsePS(output)
        #expect(entries.count == 2)
        #expect(entries[1].name == "db")
        #expect(entries[1].status.contains("Exited"))
    }

    @Test func skipsMalformedPSLines() {
        let output = "not|enough|fields\nabc333|ok|redis|Up 5 minutes"
        let entries = DockerParser.parsePS(output)
        #expect(entries.count == 1)
        #expect(entries[0].name == "ok")
    }

    @Test func parsesStatsIntoDictionaryByName() {
        let output = "web|1.23%|45.6MiB / 2GiB\ndb|0.05%|120MiB / 2GiB"
        let stats = DockerParser.parseStats(output)
        #expect(stats.count == 2)
        #expect(stats["web"]?.cpu == "1.23%")
        #expect(stats["db"]?.memory == "120MiB / 2GiB")
    }

    @Test func mergeAttachesStatsByName() {
        let ps = [DockerParser.PSEntry(id: "1", name: "web", image: "nginx", status: "Up 1 hour")]
        let stats = ["web": (cpu: "2.5%", memory: "10MiB / 1GiB")]
        let merged = DockerParser.merge(ps: ps, stats: stats)
        #expect(merged.count == 1)
        #expect(merged[0].cpuPercentText == "2.5%")
        #expect(merged[0].memoryUsageText == "10MiB / 1GiB")
        #expect(merged[0].isRunning == true)
    }

    @Test func mergeLeavesStatsNilWhenContainerNotInStats() {
        // Stopped containers appear in `docker ps` but never in `docker stats`.
        let ps = [DockerParser.PSEntry(id: "1", name: "stopped-one", image: "redis", status: "Exited (0) 1 minute ago")]
        let merged = DockerParser.merge(ps: ps, stats: [:])
        #expect(merged.count == 1)
        #expect(merged[0].cpuPercentText == nil)
        #expect(merged[0].memoryUsageText == nil)
        #expect(merged[0].isRunning == false)
    }
}
