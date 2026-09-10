# mStats — Product Requirements Document

**Author:** Kevin Hartono
**Status:** Draft v0.1
**Date:** 2026-09-10
**Reference:** iStat Menus (bjango.com/mac/istatmenus) — visual/UX benchmark only, not a code reference

---

## 1. Vision

mStats is a native macOS menu bar app that gives an at-a-glance, beautifully designed view of system vitals — CPU, GPU, memory, disk, network, sensors, battery — plus a few "delight" widgets (clock, weather, calendar) in the same visual language as the reference screenshot: dark, card-based, rounded, with live sparkline/bar graphs and ring gauges.

The app lives entirely in the macOS menu bar (top bar). Each enabled module gets its own menu bar icon/mini-graph; clicking any of them (or a combined icon) opens a dropdown panel with the full card-based dashboard.

## 2. Goals

- Feel like a first-party Apple utility: native SwiftUI, respects vibrancy/dark-light mode, no Electron/web views.
- Menu bar presence that is compact and legible even with many modules enabled.
- Dropdown dashboard that matches the reference's density and polish: rings, sparkline graphs, color-coded legends, per-process breakdowns.
- Low overhead: polling should not itself become a top CPU/memory consumer.
- Modular architecture so modules can be built, tested, and shipped incrementally.

## 3. Non-goals (v1)

- Windows/Linux support.
- Menu bar widget customization marketplace / theming engine (fixed dark theme first, light theme later).
- iCloud sync of settings across Macs.
- Historical data export / long-term logging & reporting (iStat Menus has this; defer to v2+).
- Remote/HomeKit style multi-Mac monitoring.

## 4. Target platform & tech stack

| Area | Choice | Notes |
|---|---|---|
| Min macOS version | 14.0 (Sonoma) | Enables `MenuBarExtra`, modern Swift Charts, WeatherKit v2 |
| Language | Swift 6 | Strict concurrency |
| UI | SwiftUI (+ AppKit bridge where needed) | `NSStatusItem`/`NSPopover` for menu bar items not fully covered by `MenuBarExtra`; SwiftUI for all panel content |
| Charts | Swift Charts + custom `Canvas` sparklines | Swift Charts for gauges/bars, custom lightweight `Canvas` renderer for high-frequency sparklines (network/disk) to avoid re-layout cost |
| System data | IOKit, `sysctl`, `host_statistics`, `NSProcessInfo`, `NWPathMonitor`, SMC (via IOKit `AppleSMC` user client) for temps/fans | Needs the Hardware Monitoring / SMC access approach used by open-source tools (e.g. smcFanControl-style code) — no private frameworks, no kernel extensions |
| Weather | WeatherKit | Requires Apple Developer Program enrollment + WeatherKit capability |
| Calendar | EventKit | Requires calendar access entitlement/permission prompt |
| Persistence | `UserDefaults` + `AppStorage` for settings; no database needed v1 |
| Distribution | Signed + notarized, direct download first; Mac App Store later (MAS sandboxing conflicts with raw SMC/process access — see Open Questions) |

## 5. Information architecture

- **Menu bar row**: one or more `NSStatusItem`s, one per enabled module (user can also collapse to a single combined icon). Each shows a tiny live glyph: e.g. CPU % text, a 1-line sparkline, a temperature number.
- **Dropdown panel per module**: clicking a menu bar item opens an `NSPopover`/borderless panel anchored under it, dark vibrant background, containing that module's full card.
- **Combined dashboard** (optional, reference-image style): a single click target that opens *all* cards in a responsive grid — this is the "iStat Menus preferences preview" style layout.
- **Preferences window**: standard SwiftUI `Settings` scene — module on/off, menu bar item order, update frequency, units (°C/°F, MB/s vs Mb/s), launch at login.

## 6. Feature modules (MVP scope marked ✅, later phase marked ⏭)

### 6.1 CPU ✅
- Overall usage (User/System/Idle %), stacked sparkline graph (last ~60s).
- Per-core breakdown: Efficiency cores vs Performance cores (Apple Silicon), ring or bar per core cluster.
- Top processes by CPU (name, icon, %).
- Menu bar glyph: live % text or mini bar graph.

### 6.2 Memory ✅
- Used / Wired / Compressed / App / Free breakdown (ring + legend, matches reference).
- Memory pressure indicator (green/yellow/red).
- Swap usage.
- Top processes by memory.

### 6.3 Disk ✅
- Per-volume free/used space.
- Live read/write throughput graph + peak values.
- Top processes by disk I/O (R/W columns, matches reference).

### 6.4 Network ✅
- Live upload/download throughput sparkline + peak values.
- Current Wi-Fi SSID / connection type, public IP address(es), local IP address(es).
- Per-process network usage ⏭ (stretch — requires NetworkExtension entitlement, likely v2).

### 6.5 Sensors / Fans ✅
- CPU / GPU temperature (via SMC keys).
- Fan RPM and fan speed % (where SMC exposes control/read keys).
- Battery temperature/health.

### 6.6 Battery & Power ✅
- Charge %, health %, time remaining, cycle count.
- Ring gauges matching reference "94% / 100% HEALTH" style.

### 6.7 Menu bar Clock ⏭ (phase 2)
- Multi-timezone list (like reference's stacked times).

### 6.8 Weather ⏭ (phase 2 — needs Apple Developer enrollment)
- Current conditions, hourly forecast strip, precipitation %.

### 6.9 Calendar ⏭ (phase 2 — needs EventKit permission)
- Month grid + agenda for selected day.

### 6.10 Processes overview ✅
- Combined process list (CPU/Mem/Disk/Network) sortable, reusable component across modules.

## 7. Design / UX principles

- Match reference's visual language: near-black translucent cards (`.ultraThinMaterial` / vibrancy), rounded corners (~14pt), cyan/red/purple accent palette for series (User=cyan, System=red, Compressed=purple, Free=gray — consistent per-metric color mapping across the whole app).
- Ring gauges for "current value out of known max" (CPU temp, health, battery).
- Sparkline/bar graphs for time series (CPU history, network, disk).
- Legends always show a colored dot + label + right-aligned value — consistent alignment grid across all cards.
- Typography: SF Pro, large bold numerals for headline stats (e.g. "94.2 MB/s"), small caps/uppercase gray labels for section headers (e.g. "PROCESSES").
- Respect system light/dark mode eventually, but v1 ships as a fixed dark theme to match the reference exactly.
- All panels must open with no visible layout jank — precompute card sizes, avoid pop-in.

## 8. Non-functional requirements

- Idle CPU overhead of mStats itself: < 1% average.
- Idle memory footprint: < 80MB.
- Polling interval configurable per module (default 1s for CPU/network, 2–5s for disk/sensors, since SMC reads are more expensive).
- No kernel extensions, no unsigned/unsandboxed private API usage beyond well-established SMC user-client access patterns.
- Crash-free session rate target: 99.9%.

## 9. Permissions & entitlements needed

| Capability | Requirement |
|---|---|
| SMC (temps/fans) | IOKit user client, no special entitlement, but needs careful error handling on Apple Silicon where fewer SMC keys are exposed than Intel |
| Network stats | none for throughput (via `getifaddrs`/`sysctl`), Local Network entitlement if resolving hostnames |
| EventKit | `NSCalendarsUsageDescription` + user permission prompt |
| WeatherKit | Apple Developer Program (paid) enrollment + capability in provisioning profile |
| Launch at login | `SMAppService` (macOS 13+) |

## 10. Decisions (locked 2026-09-10)

1. **Distribution target**: direct-download (.dmg) for now, unsigned during development; revisit signing/notarization/MAS before any distribution.
2. **Apple Developer Program**: not yet enrolled. WeatherKit and notarized distribution are blocked until enrollment happens — tracked as a pre-req for Phase 2/3, not Phase 1.
3. **Minimum macOS version**: **macOS 14 Sonoma+**. Menu bar shell built on SwiftUI `MenuBarExtra`.
4. **MVP feature cut**: **Core system only** — CPU, Memory, Disk, Network, Sensors/Fans, Battery. Clock/Weather/Calendar deferred to Phase 2 (blocked on Apple Developer enrollment for Weather; Calendar/Clock have no blocker and could move up if wanted).
5. **Menu bar layout**: **one `MenuBarExtra` per enabled module**, matching the reference's multiple mini-graphs, each opening its own dropdown card.

## 11. Phased roadmap

- **Phase 0 — Project scaffold**: Xcode project, app target, entitlements, base `MenuBarExtra`/`NSStatusItem` shell, design system (colors, typography, card component, ring gauge component, sparkline component).
- **Phase 1 — MVP system modules**: CPU, Memory, Disk, Network, Sensors, Battery — each as its own menu bar item + dropdown card, backed by a shared polling engine.
- **Phase 2 — Delight modules**: Clock, Weather, Calendar, combined dashboard grid view.
- **Phase 3 — Polish & ship**: Preferences window, launch-at-login, notarized DMG, (optional) MAS build.
- **Phase 4 — Advanced**: per-process network usage, historical logging/graphs, light theme, alerts/notifications on thresholds.

## 12. Success metrics

- All MVP modules show accurate, live-updating data validated against Activity Monitor / `iStats`/`istats` CLI cross-checks.
- Visual review: side-by-side with reference screenshot, card spacing/typography/color consistent.
- No SMC/IOKit crashes across Intel and Apple Silicon test machines.
