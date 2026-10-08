# HANDOFF.md

Working state of **mStats** as of **2026-10-08**, for whoever picks this up next —
most likely Kevin, but written to be readable cold.

Last commit: `f75e0a8 Report head yaw and pupil separability separately in the G0 spike`
Branch: `main`, clean, pushed to `origin`.

---

## 1. What mStats is

A native macOS menu bar system monitor (SwiftUI + AppKit), inspired by iStat Menus.
Each enabled module gets its own live menu bar icon; clicking opens a dark
card-based dropdown. Shipped modules: **CPU, Memory, Disk, Network, Sensors,
Battery, Ports, Docker, Clipboard**.

Read [`PRD/PRD.md`](PRD/PRD.md) for the original product spec and
[`PRD/gaze-focus.md`](PRD/gaze-focus.md) for the feature currently in progress.

---

## 2. Current focus: Gaze Focus

An opt-in, off-by-default feature that uses the camera to estimate which of your
displays you're looking at, then moves keyboard focus there after a short dwell.
Full reasoning in [`PRD/gaze-focus.md`](PRD/gaze-focus.md) (now at v0.2).

**Phases: G0 (prototype/measure) → G0b (signing) → G1 (MVP) → G2 (polish) → G3 (stretch).**

### Where G0 actually stands

| Spike | Status | Result |
|---|---|---|
| [`g0-capture`](PRD/spikes/g0-capture/) | Written, builds, runs. **Not measured properly.** | CPU budget looks fine. Separability unknown. |
| [`g0-windows`](PRD/spikes/g0-windows/) | Written, builds, **run and passed** | Public-API window→display mapping works. |

**The single most important open item:** head-yaw separability between two
side-by-side displays has never been measured with the protocol followed. Every
exploratory run so far had the operator facing forward, so the data is
meaningless. Everything in G1 depends on this number.

### How to run the outstanding measurement

```bash
swiftc -O -o /tmp/g0-capture PRD/spikes/g0-capture/Sources/g0capture/main.swift
/tmp/g0-capture            # --help for flags
```

Follow the protocol in [`PRD/spikes/g0-capture/README.md`](PRD/spikes/g0-capture/README.md):
sit centred between two **side-by-side** displays, look at one for the first third
of the run and the other for the last third, **actually turning your head**. Run
at least 3 times, alternating which display you start on.

Both features are reported per run — `head yaw` and `pupil offset` — because they
answer different questions (head rotation vs. true gaze) and the gap between them
is the direct test of the PRD's biggest risk row.

> Note: the printed `in-sample accuracy` fits its threshold on the same data it
> evaluates. It is optimistic by construction and does **not** validate the PRD's
> 90% target. That needs a held-out run with an unfitted threshold.

---

## 3. Findings that changed the PRD

These were discovered during G0 and are already written into
[`PRD/gaze-focus.md`](PRD/gaze-focus.md) §6.2, §6.5, §7, §11, §12. Do not
re-derive them — they are verified against the SDK.

**Vision does not give you head pose angles on this deployment target.**
`VNDetectFaceLandmarksRequest` returns `VNFaceObservation`, which has no
yaw/pitch/roll at any revision. The only head-pose angles in Vision are on the
Swift-only `FaceObservation`, gated to **macOS 15+** — and this project targets
**macOS 14** (`project.yml`). v1 must derive pose from 2D landmark geometry.
Also: pupil regions need `VNRequestFaceLandmarksConstellation76Points`, and
`VNDetectFaceLandmarksRequestRevision1` is deprecated as of macOS 13. **Pin both** —
calibration data persists against a specific point count and revision.

**Window→display mapping has no public Accessibility API.** No AX attribute
reports a window's monitor. The exact method (`SLSCopyWindows` from private
`SkyLight.framework`) would make the app un-notarizable, conflicting with §8's
notarization commitment. The public substitute — window bounds from
`CGWindowListCopyWindowInfo`, classified by display overlap — was measured and
works: 12/12 windows classified, 0 unassigned, 0 geometry disagreements. Viable
for side-by-side layouts. Note `CGDisplayBounds` and AX positions share a
top-left origin while `NSScreen.frame` is flipped bottom-left; mixing them
silently misclassifies windows.

**`kAXMain` does not work; there is no `kAXRaisedAttribute`.** The AX API exposes
only `kAXMain` and read-only `kAXFrontmost`. `kAXMain` returned
`kAXErrorUnsupportedAction` (-25205) on every app tested. `NSRunningApplication
.activate()` was the only call observed to actually move focus. **Both the spike
and §6.5 verify frontmost state after acting** rather than trusting a `.success`
return — AX calls frequently report success while changing nothing.

**Signing is a blocker, not a caveat.** `project.yml` sets
`CODE_SIGNING_ALLOWED: NO`. TCC ties Camera/Accessibility grants to the code
signature's designated requirement, so an unsigned build gets a fresh cdhash
every rebuild and loses its grants. This blocks G0 measurement and G1
development — which is why **G0b was added as its own phase**. Untouched so far.

---

## 4. Repo layout

```
mStats/
├── build.sh                    # xcodegen + xcodebuild wrapper (--release/--run/--clean)
├── project.yml                 # xcodegen project definition — GENERATED project lives here
├── Sources/mStatsApp/          # thin app target: AppDelegate, status items, entitlements
└── Packages/mStatsKit/         # all real logic, local SPM package
    └── Sources/mStatsKit/
        ├── App/AppSettings.swift        # @Observable singleton, all *Enabled flags
        ├── Engine/                      # generic poll loop + provider protocol
        ├── DesignSystem/                # CardView, RingGauge, Sparkline, Theme
        └── Modules/<Name>/              # five files per module, see CLAUDE.md
└── PRD/
    ├── PRD.md                  # original product spec (roadmap behind actual build)
    ├── gaze-focus.md           # v0.2 — current work
    └── spikes/                 # G0 harnesses, throwaway, not in the app target
```

**Two independent phase numbering schemes** exist and do not collide: the parent
PRD uses plain numbers (Phase 0–4), Gaze Focus uses `G*` (G0–G3). Note that
`PRD/PRD.md` §11 is behind the actual build — Ports, Docker, Clipboard, the
Preferences window and launch-at-login all shipped but are not on that roadmap.
Gaze Focus is not referenced from `PRD.md` at all.

---

## 5. Build, run, test

```bash
./build.sh --run                    # regenerate + build + launch
cd Packages/mStatsKit && swift test # unit tests (Swift Testing, not XCTest)
```

Verified at handoff time: **55 tests in 10 suites, all passing.**

`mStats.xcodeproj` is **generated**, never hand-edited. Re-run `xcodegen generate`
(usually via `build.sh`) whenever `project.yml` changes or files are added or
removed under `Sources/mStatsApp`.

Set `MSTATS_DEBUG_LOG=1` to make every provider print its polled snapshot to
stdout — useful for headless inspection without Console.app.

> `timeout` is not available on stock macOS, so wrap long test/build runs with
> `run_in_background` rather than `timeout 240 ...`.

---

## 6. Conventions worth knowing

- **Every module is five files**: `XProvider`, `XSnapshot`, `XViewModel`,
  `XCardView`, `XMenuBarLabel`. `poll()` must never throw — an unavailable
  reading is a case inside the snapshot, so the UI degrades instead of going dark.
- **Never write a bespoke polling loop.** `ModuleViewModel` in `Engine/` is the
  only implementation of the start/stop/interval/publish loop.
- **`AppSettings` is `@Observable`, not Combine.** Plain AppKit code can't ride
  SwiftUI body re-evaluation, so `reconcile()` polls it on a 0.5 s timer instead.
- **`reconcile()` is the single source of truth** for polling and icon state.
  Polling is gated on a module's own `xEnabled` flag, never on whether it currently
  owns a visible status item — that is why combined mode shows warm data on
  every tab. Docker is the exception: its status item also requires
  `isRunning`, but its polling must never stop, because polling *is* the
  daemon-detection mechanism.
- **The menu bar shell is raw AppKit** (`NSStatusItem` + `NSPopover`), not
  `MenuBarExtra` — the latter cannot guarantee only one dropdown is open at once.
- **Gaze Focus is the first feature to request any permission.** Clipboard
  History deliberately uses a Carbon hotkey rather than `NSEvent
  .addGlobalMonitor`, specifically to avoid the Input Monitoring prompt.

---

## 7. Suggested next steps, in order

1. **Run the G0 capture protocol 3+ times** with real head turns. Nothing else
   can be decided without it. Record both the head-yaw and pupil numbers.
2. **Do G0b — signing.** Pick a build identity (self-signed cert, or Developer ID
   if enrolment has happened) and wire it through `project.yml` + `build.sh`.
   Unblocks G1. Independent of step 1, so it can run in parallel.
3. **Read the numbers, then decide the G1 feature vector.** If pupil offset
   separates materially better than head yaw, the vector should carry both —
   this is the direct answer to the PRD's "head pose is not true gaze" risk row.
   A preliminary (unreliable) run already hinted at this.
4. **Only then start G1**, and settle the two open design questions first:
   which app "owns" a display when several have windows on it (open question #6),
   and how a switch behaves during a Space / Mission Control transition (#7).

### If you skip ahead to G1 anyway

The two things most likely to bite, both called out in the PRD:

- `GazeFocusService.start()` **must return immediately** and hand the capture
  session to its own queue. `reconcile()` runs on the main actor every 0.5 s and
  owns every status item in the app; a blocking `start()` stalls all of them.
  Camera init, `AVCaptureSession.startRunning()` and all Vision work stay off the
  main thread. This is a hard contract, not a suggestion.
- **Verify focus actually moved.** Do not trust an AX `.success` return.

---

## 8. Things not to assume

- **Anything measured by a still-sitting operator is noise.** The exploratory
  runs in §2 are recorded as preliminary signals, not results. The pupil
  observation is genuinely interesting but unproven.
- **The spikes are throwaway.** They live under `PRD/spikes/` and build with
  `swiftc` alone, deliberately outside the app target. Do not wire them into
  mStats or import them from the package.
- **In-sample accuracy is optimistic.** Never quote it against the 90% target.
- **The private-API fallback still exists** if window classification ever fails
  in the field. Reaching for `SLSCopyWindows` means giving up notarization — a
  real trade, not a fallback to take quietly.