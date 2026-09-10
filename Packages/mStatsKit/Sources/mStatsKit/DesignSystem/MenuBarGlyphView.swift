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
