# mStats — Gaze Focus (PRD)

**Author:** Kevin Hartono
**Status:** Draft v0.1
**Date:** 2026-10-07
**Parent doc:** [PRD.md](PRD.md)
**Reference:** [Glance Switch](https://glanceswitch.com/) — behavioral benchmark only, not a code reference

---

## 1. Summary

**Gaze Focus** is an opt-in mStats feature for multi-monitor users. It uses the Mac's camera to estimate which display the user is looking at and, after a short deliberate glance, moves keyboard focus (and optionally the pointer) to that display — so typing lands where the user is looking without a click first.

The feature is **off by default** and can be switched on and off at any time. While off, it does nothing: no camera session, no frame processing, no Accessibility calls.

*Name alternatives considered:* Look-to-Focus, Gaze Switch, Focus Follows Gaze. "Gaze Focus" is proposed because it names both the input (gaze) and the outcome (focus).

## 2. Problem

On a two-monitor setup, keyboard focus stays on the last-clicked window. Users glance at the other screen and start typing, and the keystrokes go to the wrong window; they must click first. This is a small but constant friction for developers, writers and traders who live across two screens.

## 3. Goals

- Switch focus to the display the user is looking at, with no click.
- Feel deliberate, not twitchy: a short dwell time and no focus stealing while the user is typing.
- Fully controllable: a clear on/off switch that actually stops all camera and Accessibility activity.
- Stay light: negligible battery and CPU impact when enabled, zero when disabled.
- Private: frames are analyzed in memory only, never saved or sent anywhere.

## 4. Non-goals (v1)

- Window-level or split-pane focus within a single display (later phase).
- True eye/gaze tracking hardware support or third-party trackers.
- Scrolling, clicking, or any pointer control by gaze beyond moving focus/pointer to the target display.
- More than 3 displays, vertical stacks and unusual arrangements (best effort only).
- Clamshell mode without an external camera (no camera available).

## 5. User stories

1. As a dual-monitor user, I turn Gaze Focus on once, calibrate in under a minute, and then focus follows my eyes between screens.
2. As a privacy-conscious user, I can turn it off in one click and be confident the camera is no longer in use.
3. As a laptop user on battery, I want it to pause itself when it can't help (single display, locked screen, asleep).
4. As a user who gets false switches, I can adjust sensitivity and dwell time, or re-calibrate.

## 5.1 Enable / disable behavior (core requirement)

| Aspect | Requirement |
|---|---|
| Default | **Off.** Fresh installs and upgrades never start the camera or prompt for permissions on their own. |
| Master toggle | `Preferences → Gaze Focus → Enable Gaze Focus`. Persisted in `AppSettings` as `gazeFocusEnabled`, following the existing `*Enabled` pattern. |
| Quick toggle | A "Gaze Focus" check item in the status item's right-click menu, plus an optional global hotkey (default unset) to toggle without opening Preferences. |
| Turning ON | Requests Camera access, then Accessibility access, only at this moment. If calibration doesn't exist yet, opens the calibration flow first. If a permission is denied, the toggle returns to off and an inline message explains why, with a button to open the relevant System Settings pane. |
| Turning OFF | Takes effect immediately: stops the `AVCaptureSession`, cancels Vision work, releases the camera (macOS camera indicator disappears), and makes no further Accessibility/pointer calls. Calibration data is kept so turning it back on doesn't require re-calibrating. |
| Auto-pause (while ON) | Capture is suspended — not just ignored — when: fewer than 2 displays are connected, the screen is locked or the display is asleep, the system is asleep, or the user is on battery in Low Power Mode (configurable). Resumes automatically. |
| State visibility | The menu bar label and card show one of: Off, Active, Paused (reason), Needs permission, Needs calibration. |
| Reset | "Reset Gaze Focus" clears calibration and learned data; it does not change the on/off state. |

## 6. How it works

1. **Capture:** `AVCaptureSession` on the built-in or external camera at low resolution (≤ 640×480) and a low frame rate (target 5–10 fps; drops to ~2 fps when idle).
2. **Estimate:** Vision face landmarks (`VNDetectFaceLandmarksRequest`) provide head yaw/pitch/roll and pupil positions, combined into a single gaze feature vector. Frames are processed in memory and discarded.
3. **Map to display:** calibration fits a mapping from the feature vector to each connected `NSScreen`. The mapping is re-evaluated when displays are connected, disconnected or rearranged.
4. **Decide:** a switch fires only when the same target display is held for the dwell time (default 300 ms), differs from the current focused display, and the user has not typed recently (default 1 s).
5. **Act:** activate the frontmost window of the target display via Accessibility (`AXUIElement`), and optionally warp the pointer there (`CGWarpMouseCursorPosition`).
6. **Learn (phase 2):** manual clicks on a display, shortly after a failed or missed switch, act as corrective samples that nudge the mapping.

### Calibration

A full-screen overlay appears on each display in turn; the user follows a dot to 5 points (corners and center), about 20 seconds per display. The result is stored locally in `UserDefaults` (feature vectors and per-display boundaries only, no images). Calibration can be re-run at any time and is offered automatically if accuracy appears poor (frequent immediate manual corrections).

## 7. Architecture fit

Gaze Focus does not fit the existing poll-based module pattern (`SystemMetricProvider` → `ModuleViewModel`), because it is driven by camera frames rather than a polling interval. Proposed shape:

- `Modules/GazeFocus/GazeFocusService` — owns the capture session and Vision pipeline; exposes `start()` / `stop()` (idempotent, like the other view models) and publishes state.
- `GazeFocusSnapshot` — `Sendable` value: state (`off | active | paused(reason) | needsPermission | needsCalibration`), current target display, last confidence.
- `GazeFocusViewModel` — `@Observable @MainActor`; bridges the service to SwiftUI and reads `AppSettings`.
- `GazeFocusCardView` — status, enable toggle, sensitivity/dwell sliders, calibrate and reset buttons.
- `GazeFocusMenuBarLabel` — small glyph reflecting state (dimmed when off or paused).
- `GazeFocusCalibrationController` (app target) — creates the per-`NSScreen` overlay windows; lives in `Sources/mStatsApp` since it owns AppKit windows.
- `AppDelegate.reconcile()` calls `gazeFocusEnabled ? service.start() : service.stop()` like every other module, so the existing 0.5 s reconcile loop remains the single source of truth.

Settings added to `AppSettings`: `gazeFocusEnabled` (default `false`), `gazeFocusDwellMs` (300), `gazeFocusTypingGuardMs` (1000), `gazeFocusMovePointer` (true), `gazeFocusPauseOnLowPower` (true), plus stored calibration data.

## 8. Permissions & entitlements

| Capability | Requirement |
|---|---|
| Camera | `NSCameraUsageDescription` added to `Info.plist` (currently absent). The app is not sandboxed today; once hardened runtime is enabled for notarization, add `com.apple.security.device.camera`. |
| Accessibility | User grants in System Settings → Privacy & Security → Accessibility. Checked with `AXIsProcessTrusted()`; prompt only when the feature is turned on. |
| Existing stance | mStats currently requests no extra permissions (see the Carbon hotkey choice for Clipboard). Gaze Focus is the first feature that does, which is why it is opt-in and requests permissions lazily. |

Unsigned or ad-hoc rebuilds can lose Camera/Accessibility grants because macOS ties them to the code signature. During development, expect re-prompts; this goes away with a stable Developer ID signature.

## 9. UX

- **Preferences section "Gaze Focus":** enable toggle, calibration status with "Calibrate…" / "Reset", dwell time, typing guard, "Also move the pointer" toggle, "Pause in Low Power Mode" toggle, and a short privacy note ("Camera frames are processed in memory and never stored or sent.").
- **Dropdown card:** state line, a live indicator of which display it currently believes you are looking at (useful for debugging calibration), and the same toggle.
- **First run:** a one-screen explainer before the first permission prompt, covering what the camera is used for and that it can be turned off anytime.
- Visual language follows the existing dark card design system (`CardView`, `LegendRow`, `Theme`).

## 10. Non-functional requirements

- **When off:** 0% CPU, no camera session, no timers beyond the existing reconcile loop.
- **When on and active:** target < 3% average CPU on Apple Silicon (a working target to validate by prototype, not a measured result); Vision work off the main thread; no frame buffering beyond the in-flight frame.
- **Latency:** glance-to-focus ≤ dwell time + 150 ms.
- **Reliability:** camera interruption (another app takes the camera, device unplugged) moves state to Paused without crashing, and recovers automatically.
- **Privacy:** no frames written to disk, no network use, no logging of image data or raw landmarks.

## 11. Risks

| Risk | Mitigation |
|---|---|
| Head pose is not true gaze; accuracy drops with lighting, glasses, distance | Dwell time, learned corrections, re-calibration, adjustable sensitivity; scope v1 to side-by-side displays |
| False switches while typing or reading | Typing guard, dwell time, hysteresis between displays |
| Battery impact on laptops | Low fps, small frames, auto-pause rules, Low Power Mode pause |
| Camera indicator and trust concerns | Opt-in, clear explainer, one-click off that really releases the camera |
| Permission loss on unsigned rebuilds | Documented dev caveat; resolves with Developer ID signing |
| Reliable window activation across apps via Accessibility | Start with "activate frontmost window of target display"; defer per-window logic |

## 12. Phased plan

- **Phase G0 — Prototype & measure:** capture + Vision at 5 fps in a throwaway target; record CPU and energy via Activity Monitor and `powermetrics`; validate yaw separability between two side-by-side displays. Go/no-go on the CPU target above.
- **Phase G1 — MVP:** enable/disable (with permission flow and auto-pause), 2-display calibration, dwell + typing guard, focus switching, Preferences section, menu bar state label.
- **Phase G2 — Polish:** learning from corrections, 3-display support, hotkey toggle, accuracy diagnostics in the card.
- **Phase G3 — Stretch:** window-level and split-pane focus within a display.

## 13. Success metrics

- Turning the feature off drops mStats camera usage to zero (verified by the camera indicator and Activity Monitor).
- ≥ 90% correct display selection after calibration in normal lighting on a two-monitor setup (manual test protocol, 50 glances).
- Fewer than 1 unintended switch per 10 minutes of normal typing and reading.
- Average CPU while active stays within the G0-validated budget.

## 14. Open questions

1. Is a pointer warp on switch wanted by default, or should focus-only be the default?
2. Should Low Power Mode auto-pause default on or off?
3. Should the feature use the built-in camera only, or let the user choose among connected cameras?
4. Is a combined-icon tab needed for Gaze Focus, or does it live only in Preferences and the right-click menu?
5. Do we gate release on Developer ID signing, given the Accessibility/Camera permission persistence issue?
