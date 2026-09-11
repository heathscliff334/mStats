import SwiftUI

/// Tiny content shown inside a MenuBarExtra's label closure — must stay
/// compact (bar height) since several modules' items sit side by side.

public struct MenuBarPercentLabel: View {
    private let systemImage: String
    private let percentText: String

    public init(systemImage: String, percent: Double?) {
        self.systemImage = systemImage
        self.percentText = percent.map { String(format: "%.0f%%", $0) } ?? "--"
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(percentText).monospacedDigit()
        }
        .foregroundStyle(.white)
    }
}

public struct MenuBarTextLabel: View {
    private let systemImage: String
    private let text: String

    public init(systemImage: String, text: String) {
        self.systemImage = systemImage
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(text).monospacedDigit()
        }
        .foregroundStyle(.white)
    }
}

public struct MenuBarSparklineLabel: View {
    private let values: [Double]
    private let systemImage: String

    public init(systemImage: String, values: [Double]) {
        self.systemImage = systemImage
        self.values = values
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
                .foregroundStyle(.white)
            SparklineGraph(series: [SparklineSeries(values: values, color: Theme.seriesUser)], style: .line)
                .frame(width: 28, height: 14)
        }
    }
}

/// A static icon with no live value — used by the combined overview status
/// item, which represents "all enabled modules" rather than one metric.
public struct MenuBarIconOnlyLabel: View {
    private let systemImage: String

    public init(systemImage: String) {
        self.systemImage = systemImage
    }

    public var body: some View {
        Image(systemName: systemImage)
            .foregroundStyle(.white)
    }
}

/// The combined-mode status item's label: the overview grid icon plus a
/// compact live readout of whichever of CPU/Memory/Battery are currently
/// enabled (each omitted entirely when its module is off). Falls back to a
/// bare icon automatically when none of the three are enabled.
public struct CombinedSummaryLabel: View {
    private let cpuPercent: Double?
    private let memoryPercent: Double?
    private let batteryPercent: Double?
    private let batteryCharging: Bool

    public init(cpuPercent: Double?, memoryPercent: Double?, batteryPercent: Double?, batteryCharging: Bool) {
        self.cpuPercent = cpuPercent
        self.memoryPercent = memoryPercent
        self.batteryPercent = batteryPercent
        self.batteryCharging = batteryCharging
    }

    public var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "square.grid.2x2")
            if let cpuPercent {
                segment(systemImage: "cpu", percent: cpuPercent)
            }
            if let memoryPercent {
                segment(systemImage: "memorychip", percent: memoryPercent)
            }
            if let batteryPercent {
                segment(systemImage: batteryCharging ? "battery.100.bolt" : "battery.100", percent: batteryPercent)
            }
        }
        .foregroundStyle(.white)
    }

    private func segment(systemImage: String, percent: Double) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
            Text(String(format: "%.0f%%", percent)).monospacedDigit()
        }
    }
}

public struct MenuBarSparklinePercentLabel: View {
    private let values: [Double]
    private let systemImage: String
    private let percentText: String

    public init(systemImage: String, values: [Double], percent: Double?) {
        self.systemImage = systemImage
        self.values = values
        self.percentText = percent.map { String(format: "%.0f%%", $0) } ?? "--"
    }

    public var body: some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            SparklineGraph(series: [SparklineSeries(values: values, color: Theme.seriesUser)], style: .line)
                .frame(width: 28, height: 14)
            Text(percentText).monospacedDigit()
        }
        .foregroundStyle(.white)
    }
}
