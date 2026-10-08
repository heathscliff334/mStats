import AppKit
import SwiftUI

public struct GazeFocusCardView: View {
    @Bindable private var viewModel: GazeFocusViewModel
    @Environment(AppSettings.self) private var settings

    public init(viewModel: GazeFocusViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        @Bindable var settings = settings
        CardView(title: "Gaze Focus") {
            Toggle("Enabled", isOn: $settings.gazeFocusEnabled)
                .toggleStyle(.switch)
                .font(Typography.legendLabel)

            HStack(spacing: 6) {
                Circle().fill(stateColor).frame(width: 8, height: 8)
                Text(viewModel.snapshot.state.label)
                    .font(Typography.legendValue)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
            }

            if let issue = viewModel.permissionIssue {
                permissionNotice(issue)
            }

            if viewModel.snapshot.state == .active {
                LegendRow(
                    color: Theme.seriesUser,
                    label: "Looking at",
                    value: viewModel.snapshot.lookingAtKey.map(viewModel.displayName(for:)) ?? "—"
                )
            }

            if let last = viewModel.snapshot.lastSwitch {
                Text(last.detail)
                    .font(Typography.caption)
                    .foregroundStyle(last.succeeded ? Theme.secondaryText : Theme.warning)
                    .lineLimit(2)
            }

            Divider().overlay(Theme.cardBorder)

            if let summary = viewModel.calibrationSummary {
                LegendRow(color: Theme.success, label: "Calibration", value: summary.quality)
            } else {
                UnavailableStateView(reason: "Not calibrated")
            }
            if let message = viewModel.calibrationMessage {
                Text(message).font(Typography.caption).foregroundStyle(Theme.warning)
            }

            HStack {
                button(viewModel.calibrationSummary == nil ? "Calibrate…" : "Recalibrate…") {
                    viewModel.requestCalibration()
                }
                if viewModel.calibrationSummary != nil {
                    button("Reset") { viewModel.resetCalibration() }
                }
            }
        }
    }

    private var stateColor: Color {
        switch viewModel.snapshot.state {
        case .active: Theme.success
        case .starting, .calibrating: Theme.seriesUser
        case .paused, .needsCalibration: Theme.warning
        case .needsPermission: Theme.critical
        case .off: Theme.secondaryText
        }
    }

    private func permissionNotice(_ permission: GazePermission) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(permission.title) access is needed. Allow mStats in System Settings, then turn Gaze Focus on again.")
                .font(Typography.caption)
                .foregroundStyle(Theme.critical)
            button("Open System Settings") { NSWorkspace.shared.open(permission.settingsURL) }
        }
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Typography.caption)
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Theme.cardBorder.opacity(1.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
