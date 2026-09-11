import SwiftUI

/// Content shown when `AppSettings.combinedIconEnabled` is on: a single
/// panel with a compact icon-tab row across the top and the selected
/// module's existing `*CardView` (reused verbatim) below it. The view models
/// passed in are the same shared instances used everywhere else — this view
/// never starts/stops polling itself, it only displays already-warm data.
public struct CombinedOverviewView: View {
    @Environment(AppSettings.self) private var settings
    private let selection: OverviewSelection

    private let cpuViewModel: CPUViewModel
    private let memoryViewModel: MemoryViewModel
    private let diskViewModel: DiskViewModel
    private let networkViewModel: NetworkViewModel
    private let sensorsViewModel: SensorsViewModel
    private let batteryViewModel: BatteryViewModel
    private let portsViewModel: PortsViewModel
    private let dockerViewModel: DockerViewModel
    private let clipboardViewModel: ClipboardViewModel

    public init(
        selection: OverviewSelection,
        cpuViewModel: CPUViewModel,
        memoryViewModel: MemoryViewModel,
        diskViewModel: DiskViewModel,
        networkViewModel: NetworkViewModel,
        sensorsViewModel: SensorsViewModel,
        batteryViewModel: BatteryViewModel,
        portsViewModel: PortsViewModel,
        dockerViewModel: DockerViewModel,
        clipboardViewModel: ClipboardViewModel
    ) {
        self.selection = selection
        self.cpuViewModel = cpuViewModel
        self.memoryViewModel = memoryViewModel
        self.diskViewModel = diskViewModel
        self.networkViewModel = networkViewModel
        self.sensorsViewModel = sensorsViewModel
        self.batteryViewModel = batteryViewModel
        self.portsViewModel = portsViewModel
        self.dockerViewModel = dockerViewModel
        self.clipboardViewModel = clipboardViewModel
    }

    private var enabledTabs: [OverviewTab] {
        OverviewTab.enabledTabs(
            cpu: settings.cpuEnabled,
            memory: settings.memoryEnabled,
            disk: settings.diskEnabled,
            network: settings.networkEnabled,
            sensors: settings.sensorsEnabled,
            battery: settings.batteryEnabled,
            ports: settings.portsEnabled,
            docker: settings.dockerEnabled,
            dockerRunning: dockerViewModel.isRunning,
            clipboard: settings.clipboardEnabled
        )
    }

    private var activeTab: OverviewTab? {
        OverviewTab.resolveSelection(preferred: selection.selectedTab, enabled: enabledTabs)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            tabBar

            switch activeTab {
            case .cpu: CPUCardView(viewModel: cpuViewModel)
            case .memory: MemoryCardView(viewModel: memoryViewModel)
            case .disk: DiskCardView(viewModel: diskViewModel)
            case .network: NetworkCardView(viewModel: networkViewModel)
            case .sensors: SensorsCardView(viewModel: sensorsViewModel)
            case .battery: BatteryCardView(viewModel: batteryViewModel)
            case .ports: PortsCardView(viewModel: portsViewModel)
            case .docker: DockerCardView(viewModel: dockerViewModel)
            case .clipboard: ClipboardCardView(viewModel: clipboardViewModel)
            case nil:
                CardView {
                    Text("No modules enabled")
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(.top, 4)
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(enabledTabs) { tab in
                Button {
                    selection.selectedTab = tab
                } label: {
                    Image(systemName: tab.systemImage)
                        .frame(width: 26, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(activeTab == tab ? Theme.seriesUser.opacity(0.25) : Color.clear)
                        )
                        .foregroundStyle(activeTab == tab ? Theme.primaryText : Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .help(tab.displayName)
            }
        }
        .padding(4)
        .frame(width: Theme.cardWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }
}
