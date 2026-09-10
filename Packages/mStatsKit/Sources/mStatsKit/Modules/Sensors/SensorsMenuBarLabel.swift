import SwiftUI

public struct SensorsMenuBarLabel: View {
    @Bindable private var viewModel: SensorsViewModel

    public init(viewModel: SensorsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        if let cpuTemp = viewModel.snapshot?.cpuTemperatureCelsius {
            MenuBarTextLabel(systemImage: "thermometer.medium", text: String(format: "%.0f°", cpuTemp))
        } else {
            MenuBarTextLabel(systemImage: "thermometer.medium", text: "--")
        }
    }
}
