import SwiftUI

public struct CPUCardView: View {
    @Bindable private var viewModel: CPUViewModel

    public init(viewModel: CPUViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        CardView {
            SparklineGraph(
                series: [
                    SparklineSeries(values: viewModel.userHistory.values, color: Theme.seriesUser),
                    SparklineSeries(values: viewModel.systemHistory.values, color: Theme.seriesSystem)
                ],
                maxValue: 100,
                style: .bar
            )

            LegendRow(color: Theme.seriesUser, label: "User", value: String(format: "%.0f%%", viewModel.snapshot.userPercent))
            LegendRow(color: Theme.seriesSystem, label: "System", value: String(format: "%.0f%%", viewModel.snapshot.systemPercent))

            Divider().overlay(Theme.cardBorder)

            if let efficiency = viewModel.snapshot.efficiencyCorePercent,
               let performance = viewModel.snapshot.performanceCorePercent {
                LegendRow(color: Theme.seriesFree, label: "Efficiency Cores", value: String(format: "%.0f%%", efficiency))
                LegendRow(color: Theme.seriesUser, label: "Performance Cores", value: String(format: "%.0f%%", performance))
            } else {
                UnavailableStateView(reason: "Core split unavailable on this Mac")
            }

            if !viewModel.snapshot.topProcesses.isEmpty {
                Divider().overlay(Theme.cardBorder)
                ProcessListView(
                    title: "Processes",
                    processes: viewModel.snapshot.topProcesses,
                    valueText: { String(format: "%.0f%%", $0.cpuUsagePercent) }
                )
            }
        }
    }
}
