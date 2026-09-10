import SwiftUI

// The menu bar shell lives entirely in AppDelegate/ModuleStatusItemController
// (AppKit NSStatusItem + NSPopover), not SwiftUI `MenuBarExtra`: MenuBarExtra
// gives no way to close one module's window when a different module's icon
// is clicked, so it can't guarantee only one dropdown is ever open at once.
// This `App` only exists to install that delegate; the `Settings` scene below
// is never shown — Preferences is opened via AppDelegate.showPreferences(),
// triggered from each status item's right-click menu.
@main
struct mStatsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}
