import SwiftUI

public struct BatteryCardView: View {
    @Bindable private var viewModel: BatteryViewModel

    public init(viewModel: BatteryViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        CardView {
            if let snap = viewModel.snapshot, snap.isPresent {
                HStack(spacing: 16) {
                    RingGauge(
                        progress: snap.chargePercent / 100,
                        color: snap.chargePercent < 20 ? Theme.critical : Theme.seriesUser,
                        primaryLabel: String(format: "%.0f%%", snap.chargePercent),
                        secondaryLabel: snap.isCharging ? "Charging" : nil
                    )
                    if let health = snap.healthPercent {
                        RingGauge(
                            progress: health / 100,
                            color: Theme.critical,
                            primaryLabel: String(format: "%.0f%%", health),
                            secondaryLabel: "Health"
                        )
                    } else {
                        UnavailableStateView(reason: "Health unavailable")
                    }
                }

                if let minutes = snap.minutesRemaining, minutes > 0 {
                    LegendRow(label: snap.isCharging ? "Time to full" : "Time remaining", value: "\(minutes / 60)h \(minutes % 60)m")
                }
                if let cycles = snap.cycleCount {
                    LegendRow(label: "Cycle Count", value: "\(cycles)")
                }
                LegendRow(label: "Power Source", value: snap.isOnACPower ? "AC Power" : "Battery")
            } else {
                UnavailableStateView(reason: "No battery detected")
            }
        }
    }
}
