import SwiftUI

public struct BatteryMenuBarLabel: View {
    @Bindable private var viewModel: BatteryViewModel

    public init(viewModel: BatteryViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        if let snap = viewModel.snapshot, snap.isPresent {
            MenuBarPercentLabel(
                systemImage: snap.isCharging ? "battery.100.bolt" : "battery.100",
                percent: snap.chargePercent
            )
        } else {
            MenuBarTextLabel(systemImage: "battery.0", text: "--")
        }
    }
}
