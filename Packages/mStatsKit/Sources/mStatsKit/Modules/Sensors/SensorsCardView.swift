import SwiftUI

public struct SensorsCardView: View {
    @Bindable private var viewModel: SensorsViewModel
    @Environment(AppSettings.self) private var settings

    public init(viewModel: SensorsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        CardView {
            HStack(spacing: 16) {
                if let cpu = viewModel.snapshot?.cpuTemperatureCelsius {
                    RingGauge(progress: min(cpu / 100, 1), color: color(for: cpu), primaryLabel: settings.temperatureUnit.format(cpu), secondaryLabel: "CPU")
                } else {
                    VStack { UnavailableStateView(reason: "CPU temp unavailable") }
                }
                if let gpu = viewModel.snapshot?.gpuTemperatureCelsius {
                    RingGauge(progress: min(gpu / 100, 1), color: color(for: gpu), primaryLabel: settings.temperatureUnit.format(gpu), secondaryLabel: "GPU")
                } else {
                    VStack { UnavailableStateView(reason: "GPU temp unavailable") }
                }
            }

            Divider().overlay(Theme.cardBorder)
            Text("Fans").sectionLabelStyle()
            if let fans = viewModel.snapshot?.fans, !fans.isEmpty {
                ForEach(fans) { fan in
                    LegendRow(label: "Fan \(fan.index + 1)", value: "\(Int(fan.currentRPM)) RPM")
                }
            } else {
                UnavailableStateView(reason: "No fans reported (fanless or unsupported)")
            }

            if let batteryTemp = viewModel.snapshot?.batteryTemperatureCelsius {
                Divider().overlay(Theme.cardBorder)
                LegendRow(label: "Battery", value: settings.temperatureUnit.format(batteryTemp))
            }
        }
    }

    private func color(for celsius: Double) -> Color {
        if celsius >= 90 { return Theme.critical }
        if celsius >= 75 { return Theme.warning }
        return Theme.seriesUser
    }
}
