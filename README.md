# mStats

A native macOS menu bar system monitor, inspired by [iStat Menus](https://bjango.com/mac/istatmenus/). Each enabled module gets its own live-updating menu bar icon; clicking it opens a dark, card-based dropdown with the full detail.

<p align="center"><img src="assets/menu-bar.png" alt="mStats menu bar icons"></p>

## Features

- 🧠 **CPU** — user/system usage, efficiency vs. performance core split (Apple Silicon), top processes.
- 🧮 **Memory** — App / Wired / Compressed / Cached Files / Free breakdown, memory pressure, swap, top processes.
- 💾 **Disk** — per-volume free/used space, live read/write throughput, top processes by disk I/O.
- 🌐 **Network** — live upload/download throughput, connection type, optional public IP lookup (off by default).
- 🌡️ **Sensors** — CPU/GPU/battery temperature, fan RPM (via SMC).
- 🔋 **Battery** — charge %, health %, cycle count, time remaining.
- 🔌 **Ports** — listening TCP/UDP ports with process/PID, search by name or port, stop (SIGTERM) or force-kill (SIGKILL).
- 🐳 **Docker** — running/stopped containers with live CPU & memory, start/stop/restart, auto-detects whether the daemon is running.
- 📋 **Clipboard History** — recent copies with one-click copy-back, global `⌘⇧V` shortcut, and automatic skipping of password-manager/concealed items.
- 👀 **Gaze Focus** *(experimental, off by default)* — on a multi-display Mac, uses the camera to tell which display you're looking at and moves keyboard focus there after a short glance. Needs Camera and Accessibility access, asked for only when you switch it on; frames are analysed in memory and never stored or sent. Can be toggled from Preferences or any menu bar icon's right-click menu. Build with `./build.sh --sign` so macOS keeps the permissions across rebuilds.
- 🧩 **Combined icon mode** — collapse every module into a single tabbed menu bar icon instead of one per module.

## Screenshots

<p align="center">
  <img src="assets/memory.png" width="32%" alt="Memory card">
  <img src="assets/disk.png" width="32%" alt="Disk card">
  <img src="assets/ports.png" width="32%" alt="Ports card">
</p>
<p align="center">
  <img src="assets/clipboard.png" width="32%" alt="Clipboard History card">
</p>

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 16+ / Swift 6

## Building

```bash
brew install xcodegen   # one-time
./build.sh --run
```

`build.sh` regenerates `mStats.xcodeproj` from `project.yml` and builds it unsigned (no Apple Developer enrollment yet — see [`PRD/PRD.md`](PRD/PRD.md) §10). Options:

| Flag | Effect |
|---|---|
| `--release` | Build the Release configuration instead of Debug |
| `--run` | Open the built `.app` once the build succeeds |
| `--clean` | Remove `./build` before building |
| `--sign` | Sign with your `Apple Development` identity (auto-detected; override with `MSTATS_SIGN_IDENTITY`) so the signature is stable across rebuilds. Needed for features that request Camera/Accessibility access, since macOS ties those grants to the signature. |

The equivalent manual commands, if you'd rather not use the script:

```bash
xcodegen generate
xcodebuild -project mStats.xcodeproj -scheme mStats -configuration Debug \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
open build/Build/Products/Debug/mStats.app
```

Run the package's unit tests directly:

```bash
cd Packages/mStatsKit && swift test
```

## Project structure

```
mStats/
├── build.sh                    # xcodegen + xcodebuild wrapper (see Building)
├── project.yml                 # xcodegen project definition
├── Sources/mStatsApp/          # thin app target (menu bar shell, entitlements)
└── Packages/mStatsKit/         # all app logic as a local Swift package
    └── Sources/mStatsKit/
        ├── Engine/              # shared polling engine, process snapshot cache
        ├── Modules/             # one folder per module (provider, view model, card view)
        ├── DesignSystem/        # shared card/ring/sparkline/legend components
        └── Settings/            # preferences UI
```

See [`PRD/PRD.md`](PRD/PRD.md) for the full product spec, architecture notes, and roadmap.

## Status

Early development. All modules above (CPU/Memory/Disk/Network/Sensors/Battery/Ports/Docker/Clipboard History) are functional. Clock, Weather, and Calendar modules, code signing/notarization, and Mac App Store distribution are not yet implemented.

## License

MIT — see [LICENSE](LICENSE).
