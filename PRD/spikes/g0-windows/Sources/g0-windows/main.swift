// G0 spike — can we reliably activate the frontmost window on a target
// display without private APIs?
//
// This is the riskiest technical assumption in PRD/gaze-focus.md, and the
// PRD understates it. §6.5 says:
//
//   "activate the frontmost window of the target display via Accessibility
//    (AXUIElement)"
//
// That reads as a single step. It is not. The hard part is not *activating*
// a window — that is a well-documented, stable Accessibility call. The
// hard part is the lookup step: **mapping a window to a display**, which
// Accessibility does not expose at all.
//
// What is and is not available:
//
//   * `AXUIElementCopyWindows` returns a flat list of every window the
//     process can see. It carries no screen, display, or geometry origin
//     that survives reliably across apps and Spaces. There is no
//     `AXDisplay`-equivalent attribute for "which monitor is this on".
//   * `kAXPositionAttribute` gives a window's frame in *global* screen
//     coordinates, which can be used to infer which display a window
//     mostly occupies. This works but is heuristic: it breaks for windows
//     straddling two displays, for full-screen windows, during Space
//     animations, and for apps that lie about their frame.
//   * The reliable way to ask "which windows are on this display" is the
//     private Screen Sharing framework (`SLSCopyWindows` from
//     `SkyLight.framework`). It is private API. It works, but an app that
//     links it cannot be notarized, and PRD §8 already commits this
//     project to a notarized distribution (§12 Phase 3 of the parent PRD).
//
// So the real question this spike answers is: **how good is the public-API
// heuristic, and what is the fallback if it is not good enough?**
//
// Build and run:
//   swiftc -O -o /tmp/g0-windows Sources/g0-windows/main.swift
//   /tmp/g0-windows            # inventory + activation attempt
//   /tmp/g0-windows --verbose  # list every window with its inferred display
//
// Requires Accessibility permission for the *parent* app (Terminal).

import AppKit
import ApplicationServices
import Foundation

// MARK: - Display inventory

/// A connected display and the frame used to classify windows against it.
///
/// `CGDisplayBounds` is in the same global, top-left-origin coordinate space
/// as the Accessibility position values, so the two can be compared
/// directly. Note that this origin is *flipped* relative to the
/// bottom-left origin AppKit uses in `NSScreen.frame`; mixing the two is a
/// classic source of "why is window 1 assigned to monitor 2" bugs. This
/// spike uses CoreGraphics frames throughout for exactly that reason.
struct DisplayInfo {
    let index: Int
    let displayID: Int
    let bounds: CGRect
    let isMain: Bool

    /// Fraction of `rect` that falls inside this display.
    func overlap(of rect: CGRect) -> Double {
        let intersection = rect.intersection(bounds)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
            return 0
        }
        let area = rect.width * rect.height
        guard area > 0 else { return 0 }
        return (intersection.width * intersection.height) / area
    }
}

enum Inventory {
    /// Enumerates connected displays via CoreGraphics.
    ///
    /// Deliberately filters out mirrored displays: a mirrored display
    /// shares its frame with the source and would otherwise register every
    /// window twice. This is the same class of bug as PRD §5.1's
    /// "fewer than 2 displays" auto-pause rule, where two mirrored screens
    /// count as two but behave as one.
    static func displays() -> [DisplayInfo] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [] }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)

        return ids.prefix(Int(count)).compactMap { id in
            let bounds = CGDisplayBounds(id)
            guard bounds.width > 0, bounds.height > 0 else { return nil }
            return DisplayInfo(
                index: Int(id),
                displayID: Int(id),
                bounds: bounds,
                isMain: CGDisplayIsMain(id) != 0
            )
        }
    }
}

// MARK: - Window enumeration

/// A window as seen through the public Accessibility API.
struct WindowInfo {
    let pid: pid_t
    let title: String
    let appName: String
    let frame: CGRect
    let element: AXUIElement
}

enum Windows {
    /// Enumerates on-screen windows for the *current* user session.
    ///
    /// Scope note: this walks only the windows of ordinary frontmost-capable
    /// apps obtained from the window list, not the full `kAXWindows` tree of
    /// every process. The full tree is what a production implementation
    /// would use, but it is slow and returns a lot of irrelevant windows
    /// (menus, tooltips, offscreen helpers). This spike keeps to the window
    /// list so the measurement stays about classification quality rather
    /// than enumeration cost.
    static func all() -> [WindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        let workspace = NSWorkspace.shared
        var results: [WindowInfo] = []

        for entry in windowList {
            guard entry[kCGWindowNumber as String] != nil,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: Any]
            else { continue }

            // Skip zero-size and off-screen windows: they are never the
            // "frontmost window of a display".
            guard let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  rect.width > 1, rect.height > 1
            else { continue }

            // A window smaller than this is almost always a panel, tooltip
            // or status item, never something to focus.
            let minSide: CGFloat = 120
            guard rect.width >= minSide, rect.height >= minSide else { continue }

            let app = workspace.runningApplications.first { $0.processIdentifier == pid }
            let appName = app?.localizedName ?? "pid \(pid)"
            let title = (entry[kCGWindowName as String] as? String) ?? "(untitled)"

            // Screen-saver / window-server windows are not focusable.
            guard app?.activationPolicy != .prohibited else { continue }

            results.append(WindowInfo(
                pid: pid,
                title: title,
                appName: appName,
                frame: rect,
                element: AXUIElementCreateApplication(pid)
            ))
        }
        return results
    }

    /// Asks the Accessibility API for a window's own frame, to check whether
    /// it agrees with the window-server bounds from `CGWindowListCopyWindowInfo`.
    ///
    /// This disagreement check matters: the PRD's activation step will use
    /// `AXUIElement` to raise a window, but the classification step uses
    /// window-server bounds. If those two disagree, the pipeline classifies
    /// on one geometry and acts on a different window than it thinks.
    static func axFrame(of appElement: AXUIElement) -> CGRect? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &value
        )
        guard status == .success, let window = value as! AXUIElement? else { return nil }

        var positionValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success, let position = positionValue else { return nil }

        var point = CGPoint.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point) else { return nil }

        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXSizeAttribute as CFString,
            &sizeValue
        ) == .success, let size = sizeValue else { return nil }

        var cgSize = CGSize.zero
        guard AXValueGetValue(size as! AXValue, .cgSize, &cgSize) else { return nil }

        return CGRect(origin: point, size: cgSize)
    }
}

// MARK: - Classification

enum Classifier {
    /// Assigns a window to the display it mostly occupies.
    ///
    /// This is the heuristic the whole feature depends on. It has no
    /// public-API alternative (see header comment): there is no
    /// Accessibility attribute that reports a window's display, so overlap
    /// fraction is the best available signal.
    ///
    /// - Parameter threshold: minimum fraction of the window that must sit
    ///   on a display for that display to win. Lower values make straddling
    ///   windows resolve to *some* display; higher values make it more
    ///   likely to return "ambiguous".
    static func display(
        for window: WindowInfo,
        among displays: [DisplayInfo],
        threshold: Double = 0.5
    ) -> DisplayInfo? {
        let ranked = displays
            .map { ($0, $0.overlap(of: window.frame)) }
            .filter { $0.1 >= threshold }
            .sorted { $0.1 > $1.1 }
        return ranked.first?.0
    }

    /// The largest window on a given display — a stand-in for "the frontmost
    /// window the user is working in".
    ///
    /// This is a crude proxy and the spike is meant to expose that: the
    /// real feature needs the *focused* window of whichever app the user
    /// last used on that display, which requires per-app
    /// `kAXFocusedWindowAttribute` queries and a policy for which app "owns"
    /// a display. Those are G1 design questions, not G0 questions.
    static func largestWindow(
        on display: DisplayInfo,
        among windows: [WindowInfo]
    ) -> WindowInfo? {
        windows
            .filter { Classifier.display(for: $0, among: [display], threshold: 0.5) != nil }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }
}

// MARK: - Activation

enum Activator {
    struct Outcome {
        let succeeded: Bool
        let detail: String
    }

    /// Raises an app and focuses its window, then verifies that the system's
    /// notion of the frontmost app actually changed.
    ///
    /// Verification matters because `AXUIElementSetAttributeValue` on
    /// `kAXMainAttribute` frequently *appears* to succeed while leaving the
    /// frontmost app untouched — the call returns `.success` and nothing
    /// happens. Only observing the change confirms the action landed.
    ///
    /// Note there is no `kAXRaisedAttribute`: the Accessibility API exposes
    /// only `kAXMain` (make frontmost) and `kAXFrontmost` (read-only). A
    /// production implementation cannot raise a window *within* a background
    /// app without first making the app frontmost — which has the side effect
    /// of bringing all of that app's windows forward. That is a real UX
    /// constraint on the feature, not an implementation detail.
    @discardableResult
    static func activate(pid: pid_t, appName: String) -> Outcome {
        let element = AXUIElementCreateApplication(pid)
        let before = NSWorkspace.shared.frontmostApplication?.processIdentifier

        // Prefer the modern activation API, which can bring a specific
        // window forward without a blanket "activate everything".
        let nsApp = NSRunningApplication(processIdentifier: pid)
        var detail = ""

        if let nsApp {
            let activated = nsApp.activate(options: [])
            detail = activated
                ? "NSRunningApplication.activate"
                : "NSRunningApplication.activate returned false"
        } else {
            detail = "NSRunningApplication not found; falling back to AX"
        }

        // Fall back to (or additionally set) the Accessibility attribute.
        let axStatus = AXUIElementSetAttributeValue(
            element,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
        if axStatus != .success {
            detail += "; kAXMain failed (\(axStatus.rawValue))"
        }

        // Give the window server a moment to settle before checking.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        let after = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard before != after else {
            return Outcome(
                succeeded: false,
                detail: "\(detail) but frontmost app unchanged (still \(appName))"
            )
        }

        return Outcome(
            succeeded: true,
            detail: "\(detail); frontmost \(before.map(String.init) ?? "?") -> \(after.map(String.init) ?? "?")"
        )
    }
}

// MARK: - Main

let verbose = CommandLine.arguments.contains("--verbose")

let displays = Inventory.displays()
let trusted = AXIsProcessTrusted()

print("=== G0 window activation spike ===")
print("Accessibility trusted: \(trusted)")
print("displays connected:    \(displays.count)")

for d in displays {
    let origin = "(\(Int(d.bounds.origin.x)),\(Int(d.bounds.origin.y)))"
    print("  display \(d.displayID) \(d.bounds.width)x\(d.bounds.height) at \(origin)\(d.isMain ? " [main]" : "")")
}

if displays.count < 2 {
    print("\nThis spike exists to test multi-display behaviour. With fewer than")
    print("2 displays it can only confirm the single-display no-op case.")
    print("Connect a second display and open a window on each.")
}

guard trusted else {
    print("\nCannot continue without Accessibility permission.")
    print("Grant your terminal app access in System Settings > Privacy &")
    print("Security > Accessibility, then re-run.")
    exit(1)
}

let windows = Windows.all()
print("\non-screen windows considered: \(windows.count)")

// Classify every window and report the distribution.
var assigned: [Int: Int] = [:]
var ambiguous = 0
for window in windows {
    if let display = Classifier.display(for: window, among: displays) {
        assigned[display.displayID, default: 0] += 1
    } else {
        ambiguous += 1
    }
}

print("\n--- classification ---")
for d in displays {
    let count = assigned[d.displayID] ?? 0
    print("  display \(d.displayID): \(count) windows")
}
print("  unassigned (straddling/below threshold): \(ambiguous)")

if verbose {
    print("\n--- every window ---")
    for window in windows.prefix(40) {
        let display = Classifier.display(for: window, among: displays)
        let label = display.map { "display \($0.displayID)" } ?? "UNASSIGNED"
        let frame = String(
            format: "%.0f,%.0f %.0fx%.0f",
            window.frame.origin.x, window.frame.origin.y,
            window.frame.width, window.frame.height
        )
        print(String(format: "  %@ — %@ [%@] %@", label, window.appName, window.title, frame))
    }
}

// Cross-check: do window-server bounds and Accessibility bounds agree?
print("\n--- geometry cross-check (CGWindowList vs AXUIElement) ---")
var checked = 0
var disagreed = 0
for window in windows.prefix(6) {
    guard let axFrame = Windows.axFrame(of: window.element) else { continue }
    checked += 1
    let dx = abs(axFrame.origin.x - window.frame.origin.x)
    let dy = abs(axFrame.origin.y - window.frame.origin.y)
    let delta = max(dx, dy)
    if delta > 2 {
        disagreed += 1
        print(String(
            format: "  %@: CGWindowList (%.0f,%.0f) vs AX (%.0f,%.0f) — delta %.0fpt",
            window.appName, window.frame.origin.x, window.frame.origin.y,
            axFrame.origin.x, axFrame.origin.y, delta
        ))
    }
}
if checked == 0 {
    print("  no windows could be cross-checked (Accessibility returned no focused window)")
} else {
    print("  checked \(checked) windows, \(disagreed) disagreed by >2pt")
}

// Attempt a real activation on the non-main display.
if displays.count >= 2 {
    let target = displays.first { !$0.isMain } ?? displays[1]
    print("\n--- activation attempt (target display \(target.displayID)) ---")

    if let candidate = Classifier.largestWindow(on: target, among: windows) {
        print("  target window: \(candidate.appName) — \(candidate.title)")
        let outcome = Activator.activate(pid: candidate.pid, appName: candidate.appName)
        print("  result: \(outcome.succeeded ? "OK" : "FAILED") — \(outcome.detail)")
    } else {
        print("  no window classified to that display — open one and re-run")
    }
} else {
    print("\n--- activation attempt ---")
    if let front = NSWorkspace.shared.frontmostApplication {
        print("  single display: would re-activate \(front.localizedName ?? "frontmost app") (no-op)")
    }
}

print("\n--- what this means ---")
print("""
Classification quality above is the real G0 finding. If every window lands
on exactly one display with few unassigned, the overlap heuristic is good
enough to build G1 on, using public API only.

If `unassigned` is high, windows are straddling displays or lying about
their frames, and the fallback is to either:
  (a) lower the threshold and accept the ambiguity, or
  (b) use `SLSCopyWindows` from the private SkyLight framework, which
      answers this exactly but makes the app un-notarizable — and PRD §8
      commits this project to a notarized distribution.

Cross-check disagreement matters independently: if CGWindowList bounds and
Accessibility bounds diverge, then the display chosen during
classification is not necessarily the display of the window that
activation raises, and a correct classifier still yields a wrong switch.
""")