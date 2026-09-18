# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

mStats is a native macOS menu bar system monitor (SwiftUI + AppKit), inspired by iStat Menus. Each enabled module (CPU, Memory, Disk, Network, Sensors, Battery, Ports, Docker, Clipboard) gets its own live-updating menu bar icon; clicking it opens a dark, card-based dropdown with full detail. See [`PRD/PRD.md`](PRD/PRD.md) for the full product spec and roadmap, and [`README.md`](README.md) for feature status.

## Commands

```bash
# Regenerate mStats.xcodeproj after editing project.yml or adding/removing files
brew install xcodegen   # one-time
xcodegen generate

# Build the app
xcodebuild -project mStats.xcodeproj -scheme mStats -configuration Debug \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build

# Run it
open build/Build/Products/Debug/mStats.app

# Run all unit tests (Swift Testing framework, not XCTest)
cd Packages/mStatsKit && swift test

# Run a single test suite or test
cd Packages/mStatsKit && swift test --filter CPUProviderTests
cd Packages/mStatsKit && swift test --filter CPUProviderTests/mixedUserSystemIdleSumsToHundred
```

Set `MSTATS_DEBUG_LOG=1` in the environment to make every provider print its polled snapshot to stdout (in addition to its `os.Logger` line), useful for headless inspection without Console.app.

xcodegen must be re-run whenever `project.yml` changes or files are added/removed under `Sources/mStatsApp` — `mStats.xcodeproj` is generated, not hand-edited.

## Architecture

The app is split into a thin app target and a local Swift package that holds all real logic:

- `Sources/mStatsApp/` — app shell only: `AppDelegate` (status item/popover lifecycle), `mStatsApp.swift` (installs the delegate), entitlements/Info.plist.
- `Packages/mStatsKit/Sources/mStatsKit/` — everything else, as a local SPM package (`swift test` runs against this package directly, independent of the Xcode project).
- `Packages/mStatsKit/Sources/CSystemShims/` — a small C target for low-level system calls providers need that aren't exposed cleanly to Swift.

### Module pattern

Every module (`Modules/CPU`, `Modules/Memory`, `Modules/Disk`, `Modules/Network`, `Modules/Sensors`, `Modules/Battery`, `Modules/Ports`, `Modules/Docker`, `Modules/Clipboard`) follows the same five-file shape:

- `XProvider` — conforms to `SystemMetricProvider` (`Engine/SystemMetricProvider.swift`). Owns any stateful diffing (previous tick counts, previous byte counters) itself. `poll()` must never throw — an unavailable reading is represented as a case inside the snapshot so the UI degrades gracefully instead of the module going dark.
- `XSnapshot` — a `Sendable` value type: the result of one poll.
- `XViewModel` — specializes the generic `ModuleViewModel<Provider>` (`Engine/ModuleViewModel.swift`), which is the *only* implementation of the start/stop/poll-interval/publish loop. Don't write a bespoke polling loop in a module; add to the generic one if it needs new behavior.
- `XCardView` — the SwiftUI content shown in the module's dropdown popover.
- `XMenuBarLabel` — the tiny live glyph rendered into the status item's icon.

Shared UI primitives (`CardView`, `RingGauge`, `SparklineGraph`, `LegendRow`, `Theme`, `Typography`) live in `DesignSystem/` and are reused across every `XCardView`.

### App-level orchestration

`AppDelegate` holds one long-lived `XViewModel` per module (so polling can continue independent of icon visibility) and, per module, an optional `ModuleStatusItemController<Label>` that owns that module's actual `NSStatusItem` + `NSPopover`.

A `reconcile()` loop runs on a 0.5s timer and is the single source of truth for both polling and icon state, driven by `AppSettings` (`@Observable`, not Combine — plain AppKit code can't ride SwiftUI body re-evaluation to observe it, so it's polled instead):

- Each module's polling is started/stopped purely by its own `xEnabled` setting, never by whether it currently owns a visible status item — so combined mode always shows warm data on every tab instead of a blank state on first switch.
- Docker is the exception: its status item additionally requires `dockerViewModel.isRunning` — polling itself *is* the daemon-detection mechanism, so it must never stop just because Docker Desktop is closed.
- When `settings.combinedIconEnabled` is on, all per-module status items are torn down and replaced by a single combined item showing `CombinedOverviewView` (tabbed); the underlying view models keep polling regardless of which icon mode is active.

The menu bar shell is built on raw AppKit (`NSStatusItem` + `NSPopover`, via `ModuleStatusItemController` and `MenuBarPanelCoordinator`), not SwiftUI `MenuBarExtra` — `MenuBarExtra` has no way to close one module's popover when a different module's icon is clicked, so it can't guarantee only one dropdown is ever open at once. `mStatsApp`'s `Settings` scene is never shown; Preferences is opened via `AppDelegate.showPreferences()` from a status item's right-click menu.

Clipboard History has a global ⌘⇧V shortcut registered via Carbon's `RegisterEventHotKey`, deliberately not `NSEvent.addGlobalMonitor` — Carbon hotkeys don't trigger the Input Monitoring/Accessibility permission prompt, which matters since the app otherwise requests no extra system permissions.

### Settings

`AppSettings` (`App/AppSettings.swift`) is an `@Observable` singleton backed by `UserDefaults`/`AppStorage`: every module's enabled flag, poll interval, and unit preferences live there.
