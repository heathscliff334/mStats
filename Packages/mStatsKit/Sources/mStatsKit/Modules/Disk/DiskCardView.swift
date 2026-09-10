import SwiftUI

public struct DiskCardView: View {
    @Bindable private var viewModel: DiskViewModel
    @Environment(AppSettings.self) private var settings

    public init(viewModel: DiskViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        CardView {
            HStack {
                VStack(alignment: .leading) {
                    Text(settings.byteRateUnit.format(viewModel.snapshot.readBytesPerSec))
                        .font(Typography.headline(20))
                        .foregroundStyle(Theme.primaryText)
                    Text("Read").font(Typography.caption).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(settings.byteRateUnit.format(viewModel.snapshot.writeBytesPerSec))
                        .font(Typography.headline(20))
                        .foregroundStyle(Theme.primaryText)
                    Text("Write").font(Typography.caption).foregroundStyle(Theme.secondaryText)
                }
            }

            SparklineGraph(
                series: [
                    SparklineSeries(values: viewModel.readHistory.values, color: Theme.seriesRead),
                    SparklineSeries(values: viewModel.writeHistory.values, color: Theme.seriesWrite)
                ],
                style: .line
            )

            LegendRow(color: Theme.seriesRead, label: "Peak Read", value: settings.byteRateUnit.format(viewModel.snapshot.peakReadBytesPerSec))
            LegendRow(color: Theme.seriesWrite, label: "Peak Write", value: settings.byteRateUnit.format(viewModel.snapshot.peakWriteBytesPerSec))

            if let usedPercent = viewModel.snapshot.primaryVolumeUsedPercent {
                LegendRow(label: "Storage Used", value: String(format: "%.0f%%", usedPercent))
            }

            if !viewModel.snapshot.volumes.isEmpty {
                Divider().overlay(Theme.cardBorder)
                Text("Volumes").sectionLabelStyle()
                ForEach(viewModel.snapshot.volumes) { volume in
                    LegendRow(label: volume.name, value: "\(Formatting.bytes(volume.availableBytes)) free")
                }
            }

            if !viewModel.snapshot.topProcesses.isEmpty {
                Divider().overlay(Theme.cardBorder)
                Text("Processes").sectionLabelStyle()
                HStack {
                    Text("").frame(maxWidth: .infinity, alignment: .leading)
                    Text("R").frame(width: 50, alignment: .trailing)
                    Text("W").frame(width: 50, alignment: .trailing)
                }
                .font(Typography.caption)
                .foregroundStyle(Theme.sectionLabel)

                ForEach(viewModel.snapshot.topProcesses.prefix(5)) { process in
                    HStack {
                        Text(process.name)
                            .font(Typography.legendLabel)
                            .foregroundStyle(Theme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        Text(Formatting.bytes(UInt64(process.diskBytesReadPerSec)))
                            .font(Typography.legendValue)
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 50, alignment: .trailing)
                        Text(Formatting.bytes(UInt64(process.diskBytesWrittenPerSec)))
                            .font(Typography.legendValue)
                            .foregroundStyle(Theme.primaryText)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }
        }
    }
}
