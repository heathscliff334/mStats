import SwiftUI

public struct NetworkCardView: View {
    @Bindable private var viewModel: NetworkViewModel
    @Environment(AppSettings.self) private var settings

    public init(viewModel: NetworkViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        CardView {
            HStack {
                VStack(alignment: .leading) {
                    Text(settings.byteRateUnit.format(viewModel.snapshot.uploadBytesPerSec))
                        .font(Typography.headline(18))
                        .foregroundStyle(Theme.primaryText)
                    Text("Upload").font(Typography.caption).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(settings.byteRateUnit.format(viewModel.snapshot.downloadBytesPerSec))
                        .font(Typography.headline(18))
                        .foregroundStyle(Theme.primaryText)
                    Text("Download").font(Typography.caption).foregroundStyle(Theme.secondaryText)
                }
            }

            SparklineGraph(
                series: [
                    SparklineSeries(values: viewModel.uploadHistory.values, color: Theme.seriesWrite),
                    SparklineSeries(values: viewModel.downloadHistory.values, color: Theme.seriesRead)
                ],
                style: .line
            )

            LegendRow(color: Theme.seriesWrite, label: "Peak Upload", value: settings.byteRateUnit.format(viewModel.snapshot.peakUploadBytesPerSec))
            LegendRow(color: Theme.seriesRead, label: "Peak Download", value: settings.byteRateUnit.format(viewModel.snapshot.peakDownloadBytesPerSec))

            Divider().overlay(Theme.cardBorder)
            LegendRow(label: "Connection", value: connectionLabel)

            if !viewModel.snapshot.localIPAddresses.isEmpty {
                Text("Local IP Addresses").sectionLabelStyle()
                ForEach(viewModel.snapshot.localIPAddresses, id: \.self) { ip in
                    CopyableValueRow(value: ip)
                }
            }

            if settings.publicIPEnabled {
                Divider().overlay(Theme.cardBorder)
                Text("Public IP Address").sectionLabelStyle()
                if let publicIP = viewModel.publicIPAddress {
                    CopyableValueRow(value: publicIP)
                } else {
                    UnavailableStateView(reason: "Looking up…")
                }
            }
        }
    }

    private var connectionLabel: String {
        switch viewModel.snapshot.connectionType {
        case .wifi: return "Wi-Fi"
        case .wired: return "Ethernet"
        case .cellular: return "Cellular"
        case .other: return "Connected"
        case .unavailable: return "Offline"
        }
    }
}
