import AppKit
import SwiftUI

/// Owns one module's `NSStatusItem` + its dropdown `NSPopover`. The status
/// item's button image is a snapshot of the module's existing SwiftUI
/// `*MenuBarLabel` view, re-rendered on the module's own poll cadence — the
/// polling/data-fetching itself is untouched and still lives entirely in the
/// module's `ModuleViewModel`; this only re-renders the already-fetched data
/// for display in the menu bar.
@MainActor
final class ModuleStatusItemController<Label: View> {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let labelBuilder: () -> Label
    private let refreshInterval: () -> TimeInterval
    private var refreshTask: Task<Void, Never>?

    init(
        labelBuilder: @escaping () -> Label,
        content: AnyView,
        refreshInterval: @escaping () -> TimeInterval
    ) {
        self.labelBuilder = labelBuilder
        self.refreshInterval = refreshInterval

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let hostingController = NSHostingController(rootView: content)
        hostingController.sizingOptions = [.preferredContentSize]
        popover.behavior = .transient
        popover.contentViewController = hostingController

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        renderLabel()
        startAutoRefresh()
    }

    func invalidate() {
        refreshTask?.cancel()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func handleClick(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu(from: button)
        } else {
            MenuBarPanelCoordinator.shared.toggle(popover, relativeTo: button)
        }
    }

    private func showContextMenu(from button: NSStatusBarButton) {
        let menu = NSMenu()
        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(AppDelegate.showPreferences), keyEquivalent: ",")
        prefsItem.target = NSApp.delegate
        menu.addItem(prefsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit mStats", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        button.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem.menu = nil
        }
    }

    private func renderLabel() {
        let renderer = ImageRenderer(content: labelBuilder().frame(height: 18).fixedSize())
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return }
        image.isTemplate = false
        statusItem.button?.image = image
    }

    private func startAutoRefresh() {
        refreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.renderLabel()
                try? await Task.sleep(for: .seconds(max(0.5, self.refreshInterval())))
            }
        }
    }
}
