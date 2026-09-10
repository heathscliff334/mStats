import AppKit

/// Ensures at most one module's dropdown popover is ever visible at a time.
/// SwiftUI's `MenuBarExtra` gives no API to close another scene's window from
/// outside, which is why the menu bar shell moved to AppKit `NSStatusItem` +
/// `NSPopover` — this coordinator is the piece that couldn't be built on top
/// of `MenuBarExtra` at all.
@MainActor
final class MenuBarPanelCoordinator: NSObject, NSPopoverDelegate {
    static let shared = MenuBarPanelCoordinator()

    private weak var currentPopover: NSPopover?

    func toggle(_ popover: NSPopover, relativeTo button: NSStatusBarButton) {
        if currentPopover === popover {
            popover.performClose(nil)
            return
        }

        currentPopover?.performClose(nil)

        popover.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        currentPopover = popover
    }

    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover, popover === currentPopover else { return }
        currentPopover = nil
    }
}
