import AppKit
import SwiftUI
import mStatsKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = AppSettings.shared

    private let cpuViewModel = CPUViewModel(settings: AppSettings.shared)
    private let memoryViewModel = MemoryViewModel(settings: AppSettings.shared)
    private let diskViewModel = DiskViewModel(settings: AppSettings.shared)
    private let networkViewModel = NetworkViewModel(settings: AppSettings.shared)
    private let sensorsViewModel = SensorsViewModel(settings: AppSettings.shared)
    private let batteryViewModel = BatteryViewModel(settings: AppSettings.shared)

    private var cpuItem: ModuleStatusItemController<CPUMenuBarLabel>?
    private var memoryItem: ModuleStatusItemController<MemoryMenuBarLabel>?
    private var diskItem: ModuleStatusItemController<DiskMenuBarLabel>?
    private var networkItem: ModuleStatusItemController<NetworkMenuBarLabel>?
    private var sensorsItem: ModuleStatusItemController<SensorsMenuBarLabel>?
    private var batteryItem: ModuleStatusItemController<BatteryMenuBarLabel>?

    private var preferencesWindowController: PreferencesWindowController?

    // AppSettings is @Observable, not a Combine publisher, and this is plain
    // AppKit (no SwiftUI body re-evaluation to ride on) — reconciling desired
    // vs actual status items on a lightweight poll is simpler and more
    // robust here than fighting withObservationTracking's fire-once semantics
    // from outside a SwiftUI view.
    private var reconcileTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        preferencesWindowController = PreferencesWindowController(settings: settings)

        reconcile()
        reconcileTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.5))
                self.reconcile()
            }
        }
    }

    @objc func showPreferences() {
        preferencesWindowController?.show()
    }

    private func reconcile() {
        syncItem(enabled: settings.cpuEnabled, existing: &cpuItem) { [self] in
            cpuViewModel.start()
            return ModuleStatusItemController(
                labelBuilder: { CPUMenuBarLabel(viewModel: self.cpuViewModel) },
                content: AnyView(CPUCardView(viewModel: cpuViewModel).environment(settings)),
                refreshInterval: { self.settings.cpuPollInterval }
            )
        }

        syncItem(enabled: settings.memoryEnabled, existing: &memoryItem) { [self] in
            memoryViewModel.start()
            return ModuleStatusItemController(
                labelBuilder: { MemoryMenuBarLabel(viewModel: self.memoryViewModel) },
                content: AnyView(MemoryCardView(viewModel: memoryViewModel).environment(settings)),
                refreshInterval: { self.settings.memoryPollInterval }
            )
        }

        syncItem(enabled: settings.diskEnabled, existing: &diskItem) { [self] in
            diskViewModel.start()
            return ModuleStatusItemController(
                labelBuilder: { DiskMenuBarLabel(viewModel: self.diskViewModel) },
                content: AnyView(DiskCardView(viewModel: diskViewModel).environment(settings)),
                refreshInterval: { self.settings.diskPollInterval }
            )
        }

        syncItem(enabled: settings.networkEnabled, existing: &networkItem) { [self] in
            networkViewModel.start()
            return ModuleStatusItemController(
                labelBuilder: { NetworkMenuBarLabel(viewModel: self.networkViewModel) },
                content: AnyView(NetworkCardView(viewModel: networkViewModel).environment(settings)),
                refreshInterval: { self.settings.networkPollInterval }
            )
        }

        syncItem(enabled: settings.sensorsEnabled, existing: &sensorsItem) { [self] in
            sensorsViewModel.start()
            return ModuleStatusItemController(
                labelBuilder: { SensorsMenuBarLabel(viewModel: self.sensorsViewModel) },
                content: AnyView(SensorsCardView(viewModel: sensorsViewModel).environment(settings)),
                refreshInterval: { self.settings.sensorsPollInterval }
            )
        }

        syncItem(enabled: settings.batteryEnabled, existing: &batteryItem) { [self] in
            batteryViewModel.start()
            return ModuleStatusItemController(
                labelBuilder: { BatteryMenuBarLabel(viewModel: self.batteryViewModel) },
                content: AnyView(BatteryCardView(viewModel: batteryViewModel).environment(settings)),
                refreshInterval: { self.settings.batteryPollInterval }
            )
        }
    }

    private func syncItem<Label: View>(
        enabled: Bool,
        existing: inout ModuleStatusItemController<Label>?,
        make: () -> ModuleStatusItemController<Label>
    ) {
        if enabled, existing == nil {
            existing = make()
        } else if !enabled, let item = existing {
            item.invalidate()
            existing = nil
        }
    }
}
