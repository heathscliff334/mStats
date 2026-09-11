import Foundation

/// Detects whether Docker Desktop's daemon is reachable and, if so, lists
/// all containers, running and stopped (`docker ps -a`), with live stats for
/// the running ones — by shelling out to the `docker` CLI
/// (there's no lightweight syscall for this; the CLI already speaks to
/// whatever socket Docker Desktop configured). Every `Process` invocation is
/// raced against a timeout so a wedged daemon can never hang the app's
/// polling loop.
public actor DockerProvider: SystemMetricProvider {
    public init() {}

    public func poll() async -> DockerSnapshot {
        guard let dockerPath = Self.resolvedDockerPath else {
            return .notRunning
        }

        let info = await Self.run(dockerPath, ["info", "--format", "{{.ServerVersion}}"], timeout: 2.0)
        guard info.succeeded else {
            return .notRunning
        }

        async let psResult = Self.run(dockerPath, ["ps", "-a", "--format", "{{.ID}}|{{.Names}}|{{.Image}}|{{.Status}}"], timeout: 3.0)
        async let statsResult = Self.run(dockerPath, ["stats", "--no-stream", "--format", "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}"], timeout: 3.0)

        let ps = await psResult
        let stats = await statsResult

        let entries = DockerParser.merge(
            ps: DockerParser.parsePS(ps.output),
            stats: DockerParser.parseStats(stats.output)
        )
        return DockerSnapshot(isRunning: true, containers: entries.sorted { $0.name < $1.name })
    }

    public enum ActionResult: Sendable, Equatable {
        case success
        case failed(String)
    }

    public func start(containerID: String) async -> ActionResult {
        await performAction(["start", containerID])
    }

    public func stop(containerID: String) async -> ActionResult {
        await performAction(["stop", containerID])
    }

    public func restart(containerID: String) async -> ActionResult {
        await performAction(["restart", containerID])
    }

    private func performAction(_ arguments: [String]) async -> ActionResult {
        guard let dockerPath = Self.resolvedDockerPath else {
            return .failed("Docker CLI not found")
        }
        let result = await Self.run(dockerPath, arguments, timeout: 10.0)
        if result.succeeded {
            return .success
        }
        let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return .failed(message.isEmpty ? "Command failed" : message)
    }

    /// Docker Desktop doesn't always land its `docker` symlink on a GUI
    /// app's inherited PATH (Homebrew and `~/.docker/bin` locations vary),
    /// so a fixed candidate list is checked directly rather than relying on
    /// `$PATH`/`which`. Resolved once and cached for the process lifetime.
    private static let resolvedDockerPath: String? = {
        let candidates = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            NSHomeDirectory() + "/.docker/bin/docker",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    /// Runs `executable` with `arguments`, racing completion against
    /// `timeout` — if the process hasn't finished by then it's terminated
    /// and treated as a failure, so a wedged daemon can never hang a poll.
    private static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async -> (output: String, succeeded: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        guard (try? process.run()) != nil else { return ("", false) }

        return await withTaskGroup(of: (String, Bool)?.self) { group in
            group.addTask {
                let outData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let succeeded = process.terminationStatus == 0
                let text = String(data: succeeded ? outData : errData, encoding: .utf8) ?? ""
                return (text, succeeded)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }

            defer { group.cancelAll() }
            guard let first = await group.next() else { return ("", false) }
            if let first {
                return first
            }
            if process.isRunning {
                process.terminate()
            }
            return ("timed out", false)
        }
    }
}
