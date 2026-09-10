import AppKit
import SwiftUI
import mStatsKit

/// mStats is `LSUIElement` (accessory app, no Dock icon / app menu bar), so
/// there is no automatic "Settings…" menu item to open a SwiftUI `Settings`
/// scene. This owns a plain `NSWindow` shown from each status item's
/// right-click menu instead.
@MainActor
final class PreferencesWindowController: NSWindowController {
    convenience init(settings: AppSettings) {
        let hosting = NSHostingController(rootView: PreferencesView(settings: settings))
        let window = NSWindow(contentViewController: hosting)
        window.title = "mStats Preferences"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    func show() {
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
