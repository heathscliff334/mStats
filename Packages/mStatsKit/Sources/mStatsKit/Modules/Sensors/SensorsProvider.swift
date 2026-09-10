import Foundation

public struct SensorsProvider: SystemMetricProvider {
    public init() {}

    public func poll() async -> SensorsSnapshot {
        let client = SMCClient.shared
        let cpuTemp = await client.readTemperature(candidateKeys: SMCKeys.cpuTemperatureCandidates)
        let gpuTemp = await client.readTemperature(candidateKeys: SMCKeys.gpuTemperatureCandidates)
        let batteryTemp = await client.readTemperature(candidateKeys: SMCKeys.batteryTemperatureCandidates)

        var fans: [FanReading] = []
        if let count = await client.fanCount(), count > 0 {
            for index in 0..<count {
                if let (current, target) = await client.fanSpeed(index: index) {
                    fans.append(FanReading(index: index, currentRPM: current, targetRPM: target))
                }
            }
        }

        return SensorsSnapshot(
            cpuTemperatureCelsius: cpuTemp,
            gpuTemperatureCelsius: gpuTemp,
            batteryTemperatureCelsius: batteryTemp,
            fans: fans
        )
    }
}
