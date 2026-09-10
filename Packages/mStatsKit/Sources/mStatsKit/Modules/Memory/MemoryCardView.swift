import SwiftUI

public struct MemoryCardView: View {
    @Bindable private var viewModel: MemoryViewModel

    public init(viewModel: MemoryViewModel) {
        self.viewModel = viewModel
    }

    private var snap: MemorySnapshot { viewModel.snapshot ?? .empty }

    private var usedFraction: Double { snap.usedFraction }

    public var body: some View {
        CardView {
            HStack(spacing: 16) {
                RingGauge(
                    progress: usedFraction,
                    color: pressureColor,
                    primaryLabel: String(format: "%.0f%%", usedFraction * 100),
                    secondaryLabel: "MEMORY"
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(pressureLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(pressureColor)
                    Text(Formatting.bytes(snap.totalBytes) + " total")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            LegendRow(color: Theme.seriesUser, label: "App", value: Formatting.bytes(snap.appBytes))
            LegendRow(color: Theme.seriesSystem, label: "Wired", value: Formatting.bytes(snap.wiredBytes))
            LegendRow(color: Theme.seriesCompressed, label: "Compressed", value: Formatting.bytes(snap.compressedBytes))
            LegendRow(color: Theme.seriesCachedFiles, label: "Cached Files", value: Formatting.bytes(snap.cachedFilesBytes))
            LegendRow(color: Theme.seriesFree, label: "Free", value: Formatting.bytes(snap.freeBytes))

            if snap.swapTotalBytes > 0 {
                Divider().overlay(Theme.cardBorder)
                LegendRow(label: "Swap Used", value: "\(Formatting.bytes(snap.swapUsedBytes)) / \(Formatting.bytes(snap.swapTotalBytes))")
            }

            if !snap.topProcesses.isEmpty {
                Divider().overlay(Theme.cardBorder)
                ProcessListView(
                    title: "Processes",
                    processes: snap.topProcesses,
                    valueText: { Formatting.bytes($0.residentMemoryBytes) }
                )
            }
        }
    }

    private var pressureColor: Color {
        switch snap.pressureLevel {
        case .normal: return Theme.seriesUser
        case .warning: return Theme.warning
        case .critical: return Theme.critical
        }
    }

    private var pressureLabel: String {
        switch snap.pressureLevel {
        case .normal: return "Memory Pressure: Normal"
        case .warning: return "Memory Pressure: Warning"
        case .critical: return "Memory Pressure: Critical"
        }
    }
}
