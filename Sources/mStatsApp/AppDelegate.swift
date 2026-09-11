import AppKit
import Carbon.HIToolbox
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
    private let portsViewModel = PortsViewModel(settings: AppSettings.shared)
    private let dockerViewModel = DockerViewModel(settings: AppSettings.shared)
    private let clipboardViewModel = ClipboardViewModel(settings: AppSettings.shared)

    private var cpuItem: ModuleStatusItemController<CPUMenuBarLabel>?
    private var memoryItem: ModuleStatusItemController<MemoryMenuBarLabel>?
    private var diskItem: ModuleStatusItemController<DiskMenuBarLabel>?
    private var networkItem: ModuleStatusItemController<NetworkMenuBarLabel>?
    private var sensorsItem: ModuleStatusItemController<SensorsMenuBarLabel>?
    private var batteryItem: ModuleStatusItemController<BatteryMenuBarLabel>?
    private var portsItem: ModuleStatusItemController<PortsMenuBarLabel>?
    private var dockerItem: ModuleStatusItemController<DockerMenuBarLabel>?
    private var clipboardItem: ModuleStatusItemController<ClipboardMenuBarLabel>?
    private var combinedItem: ModuleStatusItemController<CombinedSummaryLabel>?

    /// Shared with `CombinedOverviewView` so the global Clipboard hotkey can
    /// force the panel to that tab before showing it, even though tab
    /// selection is otherwise the view's own concern.
    private let overviewSelection = OverviewSelection()

    private var preferencesWindowController: PreferencesWindowController?

    private var clipboardHotKeyRef: EventHotKeyRef?
    private var clipboardHotKeyHandlerRef: EventHandlerRef?

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

        registerClipboardHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let clipboardHotKeyRef {
            UnregisterEventHotKey(clipboardHotKeyRef)
        }
        if let clipboardHotKeyHandlerRef {
            RemoveEventHandler(clipboardHotKeyHandlerRef)
        }
    }

    @objc func showPreferences() {
        preferencesWindowController?.show()
    }

    // MARK: - Clipboard global shortcut

    /// ⌘⇧V opens Clipboard History from anywhere, without requiring the
    /// Input Monitoring/Accessibility permission `NSEvent.addGlobalMonitor`
    /// would need — Carbon hotkeys are exempt from that prompt, which matters
    /// since this app otherwise asks for no extra system permissions.
    private func registerClipboardHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    delegate.handleClipboardHotKey()
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &clipboardHotKeyHandlerRef
        )
        guard installStatus == noErr else {
            print("[Hotkey] InstallEventHandler failed: \(installStatus)")
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x6d53_7443), id: 1) // 'mStC'
        let modifiers = UInt32(cmdKey | shiftKey)
        let keyCode = UInt32(kVK_ANSI_V)
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &clipboardHotKeyRef)
        if registerStatus != noErr {
            print("[Hotkey] RegisterEventHotKey failed: \(registerStatus)")
        } else {
            print("[Hotkey] Registered ⌘⇧V for Clipboard History")
        }
    }

    private func handleClipboardHotKey() {
        guard settings.clipboardEnabled else {
            NSSound.beep()
            return
        }

        if settings.combinedIconEnabled {
            if combinedItem == nil {
                combinedItem = makeCombinedItem()
            }
            overviewSelection.selectedTab = .clipboard
            combinedItem?.show()
        } else {
            if clipboardItem == nil {
                clipboardItem = makeClipboardItem()
            }
            clipboardItem?.show()
        }
    }

    private func reconcile() {
        // Polling is tied purely to each module's own `xEnabled` flag, never
        // to whether it currently owns a visible status item — so combined
        // mode always shows live, already-warm data on every tab, not a
        // blank state on first switch. start()/stop() are both idempotent.
        settings.cpuEnabled ? cpuViewModel.start() : cpuViewModel.stop()
        settings.memoryEnabled ? memoryViewModel.start() : memoryViewModel.stop()
        settings.diskEnabled ? diskViewModel.start() : diskViewModel.stop()
        settings.networkEnabled ? networkViewModel.start() : networkViewModel.stop()
        settings.sensorsEnabled ? sensorsViewModel.start() : sensorsViewModel.stop()
        settings.batteryEnabled ? batteryViewModel.start() : batteryViewModel.stop()
        settings.portsEnabled ? portsViewModel.start() : portsViewModel.stopPolling()
        // Docker polls whenever enabled, independent of whether the daemon
        // is currently detected running — polling IS the detection
        // mechanism (see DockerProvider.poll), so it can never stop just
        // because Docker Desktop happens to be closed right now.
        settings.dockerEnabled ? dockerViewModel.startPolling() : dockerViewModel.stopPolling()
        settings.clipboardEnabled ? clipboardViewModel.startPolling() : clipboardViewModel.stopPolling()

        if settings.combinedIconEnabled {
            // One shared icon; the per-module icons are torn down entirely
            // (their view models keep polling above, independent of this).
            if combinedItem == nil {
                combinedItem = makeCombinedItem()
            }
            teardown(&cpuItem)
            teardown(&memoryItem)
            teardown(&diskItem)
            teardown(&networkItem)
            teardown(&sensorsItem)
            teardown(&batteryItem)
            teardown(&portsItem)
            teardown(&dockerItem)
            teardown(&clipboardItem)
            return
        }

        teardown(&combinedItem)
        syncItem(enabled: settings.cpuEnabled, existing: &cpuItem, make: makeCPUItem)
        syncItem(enabled: settings.memoryEnabled, existing: &memoryItem, make: makeMemoryItem)
        syncItem(enabled: settings.diskEnabled, existing: &diskItem, make: makeDiskItem)
        syncItem(enabled: settings.networkEnabled, existing: &networkItem, make: makeNetworkItem)
        syncItem(enabled: settings.sensorsEnabled, existing: &sensorsItem, make: makeSensorsItem)
        syncItem(enabled: settings.batteryEnabled, existing: &batteryItem, make: makeBatteryItem)
        syncItem(enabled: settings.portsEnabled, existing: &portsItem, make: makePortsItem)
        // Docker's icon additionally requires live detection — this is the
        // one module whose menu bar presence isn't purely its own toggle.
        syncItem(enabled: settings.dockerEnabled && dockerViewModel.isRunning, existing: &dockerItem, make: makeDockerItem)
        syncItem(enabled: settings.clipboardEnabled, existing: &clipboardItem, make: makeClipboardItem)
    }

    private func makeCPUItem() -> ModuleStatusItemController<CPUMenuBarLabel> {
        ModuleStatusItemController(
            labelBuilder: { CPUMenuBarLabel(viewModel: self.cpuViewModel) },
            content: AnyView(CPUCardView(viewModel: cpuViewModel).environment(settings)),
            refreshInterval: { self.settings.cpuPollInterval }
        )
    }

    private func makeMemoryItem() -> ModuleStatusItemController<MemoryMenuBarLabel> {
        ModuleStatusItemController(
            labelBuilder: { MemoryMenuBarLabel(viewModel: self.memoryViewModel) },
            content: AnyView(MemoryCardView(viewModel: memoryViewModel).environment(settings)),
            refreshInterval: { self.settings.memoryPollInterval }
        )
    }

    private func makeDiskItem() -> ModuleStatusItemController<DiskMenuBarLabel> {
        ModuleStatusItemController(
            labelBuilder: { DiskMenuBarLabel(viewModel: self.diskViewModel) },
            content: AnyView(DiskCardView(viewModel: diskViewModel).environment(settings)),
            refreshInterval: { self.settings.diskPollInterval }
        )
    }

    private func makeNetworkItem() -> ModuleStatusItemController<NetworkMenuBarLabel> {
        ModuleStatusItemController(
            labelBuilder: { NetworkMenuBarLabel(viewModel: self.networkViewModel) },
            content: AnyView(NetworkCardView(viewModel: networkViewModel).environment(settings)),
            refreshInterval: { self.settings.networkPollInterval }
        )
    }

    private func makeSensorsItem() -> ModuleStatusItemController<SensorsMenuBarLabel> {
        ModuleStatusItemController(
            labelBuilder: { SensorsMenuBarLabel(viewModel: self.sensorsViewModel) },
            content: AnyView(SensorsCardView(viewModel: sensorsViewModel).environment(settings)),
            refreshInterval: { self.settings.sensorsPollInterval }
        )
    }

    private func makeBatteryItem() -> ModuleStatusItemController<BatteryMenuBarLabel> {
        ModuleStatusItemController(
            labelBuilder: { BatteryMenuBarLabel(viewModel: self.batteryViewModel) },
            content: AnyView(BatteryCardView(viewModel: batteryViewModel).environment(settings)),
            refreshInterval: { self.settings.batteryPollInterval }
        )
    }

    private func makePortsItem() -> ModuleStatusItemController<PortsMenuBarLabel> {
        ModuleStatusItemController(
            labelBuilder: { PortsMenuBarLabel(viewModel: self.portsViewModel) },
            content: AnyView(PortsCardView(viewModel: portsViewModel).environment(settings)),
            refreshInterval: { self.settings.portsPollInterval }
        )
    }

    private func makeDockerItem() -> ModuleStatusItemController<DockerMenuBarLabel> {
        ModuleStatusItemController(
            labelBuilder: { DockerMenuBarLabel(viewModel: self.dockerViewModel) },
            content: AnyView(DockerCardView(viewModel: dockerViewModel).environment(settings)),
            refreshInterval: { self.settings.dockerPollInterval }
        )
    }

    private func makeClipboardItem() -> ModuleStatusItemController<ClipboardMenuBarLabel> {
        ModuleStatusItemController(
            labelBuilder: { ClipboardMenuBarLabel(viewModel: self.clipboardViewModel) },
            content: AnyView(ClipboardCardView(viewModel: clipboardViewModel).environment(settings)),
            refreshInterval: { 5 }
        )
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

    private func teardown<Label: View>(_ item: inout ModuleStatusItemController<Label>?) {
        item?.invalidate()
        item = nil
    }

    private func makeCombinedItem() -> ModuleStatusItemController<CombinedSummaryLabel> {
        ModuleStatusItemController(
            labelBuilder: {
                CombinedSummaryLabel(
                    cpuPercent: self.settings.cpuEnabled
                        ? self.cpuViewModel.snapshot.userPercent + self.cpuViewModel.snapshot.systemPercent
                        : nil,
                    memoryPercent: self.settings.memoryEnabled
                        ? self.memoryViewModel.snapshot.map { $0.usedFraction * 100 }
                        : nil,
                    batteryPercent: (self.settings.batteryEnabled && (self.batteryViewModel.snapshot?.isPresent ?? false))
                        ? self.batteryViewModel.snapshot?.chargePercent
                        : nil,
                    batteryCharging: self.batteryViewModel.snapshot?.isCharging ?? false
                )
            },
            content: AnyView(
                CombinedOverviewView(
                    selection: overviewSelection,
                    cpuViewModel: cpuViewModel,
                    memoryViewModel: memoryViewModel,
                    diskViewModel: diskViewModel,
                    networkViewModel: networkViewModel,
                    sensorsViewModel: sensorsViewModel,
                    batteryViewModel: batteryViewModel,
                    portsViewModel: portsViewModel,
                    dockerViewModel: dockerViewModel,
                    clipboardViewModel: clipboardViewModel
                ).environment(settings)
            ),
            refreshInterval: { 3 }
        )
    }
}
