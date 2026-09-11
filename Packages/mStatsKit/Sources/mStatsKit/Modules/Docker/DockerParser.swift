import Foundation

/// Pure parser for `docker ps`/`docker stats` textual output, extracted so
/// it's testable against fixture text without shelling out. Both commands
/// are invoked with explicit `--format` strings (not the default table), one
/// field per line separated by `|`:
///   ps:    `{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}`
///   stats: `{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}`
/// Joined by container name rather than ID — `docker ps`'s `.ID` truncation
/// behavior isn't guaranteed stable across versions, but names are unique
/// and reported identically by both commands.
enum DockerParser {
    struct PSEntry {
        let id: String
        let name: String
        let image: String
        let status: String
    }

    static func parsePS(_ output: String) -> [PSEntry] {
        output.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4 else { return nil }
            return PSEntry(id: fields[0], name: fields[1], image: fields[2], status: fields[3])
        }
    }

    /// name -> (cpuPercentText, memoryUsageText)
    static func parseStats(_ output: String) -> [String: (cpu: String, memory: String)] {
        var result: [String: (cpu: String, memory: String)] = [:]
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 3 else { continue }
            result[fields[0]] = (cpu: fields[1], memory: fields[2])
        }
        return result
    }

    static func merge(ps: [PSEntry], stats: [String: (cpu: String, memory: String)]) -> [ContainerEntry] {
        ps.map { entry in
            let stat = stats[entry.name]
            return ContainerEntry(
                id: entry.id,
                name: entry.name,
                image: entry.image,
                status: entry.status,
                cpuPercentText: stat?.cpu,
                memoryUsageText: stat?.memory
            )
        }
    }
}
