# G0 spike — window activation

Phase G0 of [`PRD/gaze-focus.md`](../../gaze-focus.md) §12, and the highest-risk
spike in the phase. PRD §6.5 states the activation step as if it were one step:

> activate the frontmost window of the target display via Accessibility (`AXUIElement`)

It is two, and the second is the hard one.

## What this spike exists to settle

**Mapping a window to a display is not an Accessibility operation.** There is no
Accessibility attribute that reports which monitor a window is on. The spike
measures how good the best public-API substitute can be, because that determines
whether G1 is buildable without private APIs:

| Approach | Status | Trade-off |
|---|---|---|
| `SLSCopyWindows` (`SkyLight.framework`) | Private API | Answers exactly, but makes the app **un-notarizable** — and PRD §8 commits this project to notarized distribution |
| `CGWindowListCopyWindowInfo` bounds + overlap heuristic | Public | Heuristic; degrades on straddling windows, full-screen windows, Space transitions |
| Accessibility `kAXPositionAttribute` | Public | Same geometry source as above, more expensive, and returns only the *focused* window per app |

If the public heuristic holds up, G1 can be built entirely on public API. That is
the finding this spike is after.

## Build and run

```bash
cd PRD/spikes/g0-windows
swiftc -O -o /tmp/g0-windows Sources/g0-windows/main.swift
/tmp/g0-windows --help
/tmp/g0-windows            # inventory + classification + activation attempt
/tmp/g0-windows --verbose  # list every window with its inferred display
```

Requires Accessibility permission for the **parent app** (Terminal/iTerm) in
System Settings → Privacy & Security → Accessibility. This is a real prompt
because the binary is unsigned — the same signature caveat as PRD §8, and the
reason signing needs to happen before G1 rather than after.

Have at least one window open on each display before running, or the activation
attempt has no target.

## What to look at

**`unassigned` is the headline number.** Every on-screen window should land on
exactly one display. Windows that fall below the overlap threshold are the ones
that would break a real switch — they straddle displays, are in a Space
transition, or report a frame that does not match reality.

**`geometry cross-check` is independently important.** It compares
`CGWindowListCopyWindowInfo` bounds against the Accessibility `kAXPosition` value
for the same window. If they disagree, then the display chosen during
classification is not necessarily the display of the window that activation
raises — a *correct classifier* still produces a *wrong switch*. This is the
failure mode most likely to be mistaken for a classifier bug.

## The two findings already confirmed on this machine

1. **Classification is clean.** 12 windows, 0 unassigned, clean split across both
   displays. The overlap heuristic holds for side-by-side arrangements.

2. **`kAXMain` is unsupported, `NSRunningApplication.activate` works.**
   `AXUIElementSetAttributeValue(kAXMain)` returned `-25205`
   (`kAXErrorUnsupportedAction`) on every app tested. `NSRunningApplication
   .activate(options: [])` succeeded and the frontmost process actually changed,
   which the spike verifies rather than trusting the return value.

   There is also **no `kAXRaisedAttribute`** in the Accessibility API — only
   `kAXMain` (make frontmost) and `kAXFrontmost` (read-only). A production
   implementation cannot raise a window *within* a background app without first
   making that app frontmost, which brings all of its windows forward. That is a
   UX constraint on the feature, not an implementation detail.

## Why the spike verifies instead of trusting return values

`AXUIElementSetAttributeValue` frequently returns `.success` while leaving the
frontmost application unchanged. The spike reads `NSWorkspace.frontmostApplication`
before and after, and treats "call succeeded but nothing moved" as a **failure**.
Any production implementation of §6.5 must do the same, or it will report success
on switches that never happened.

## Known limits of this spike

Deliberately scoped to the questions G0 needs answered. All of these are G1 design
questions, not gaps in the measurement:

- Window enumeration uses the window list, not the full per-process
  `kAXWindows` tree. The full tree is what production needs; it is slower and
  returns many irrelevant windows.
- "Frontmost window on a display" is approximated as the **largest** window there.
  Real behaviour needs per-app `kAXFocusedWindowAttribute` queries plus a policy
  for which app "owns" a display.
- No Space / Mission Control guard. A switch during a Space transition will
  produce a visibly wrong result, and the spike does not detect that case.

## Coordinate space warning

The spike uses CoreGraphics display bounds throughout, because
`CGDisplayBounds` and Accessibility's `kAXPosition` share a global top-left
origin, while `NSScreen.frame` uses a flipped bottom-left origin. Mixing the two
is the classic cause of "window on the left monitor classified to the right one".
Any G1 implementation that reaches for `NSScreen.frame` for this comparison will
get it wrong.