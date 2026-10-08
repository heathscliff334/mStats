import CoreGraphics
import Foundation

/// A connected display. `bounds` is in CoreGraphics global coordinates (origin
/// top-left of the main display, y down) — the same space as window bounds from
/// `CGWindowListCopyWindowInfo` and Accessibility positions. `NSScreen.frame`
/// is bottom-left flipped; never mix the two when classifying windows.
public struct GazeDisplay: Sendable, Equatable {
    public var key: String
    public var name: String
    public var bounds: CGRect

    public init(key: String, name: String, bounds: CGRect) {
        self.key = key
        self.name = name
        self.bounds = bounds
    }
}

public struct GazeWindow: Sendable, Equatable {
    public var pid: Int32
    public var ownerName: String
    public var bounds: CGRect
    public var layer: Int

    public init(pid: Int32, ownerName: String, bounds: CGRect, layer: Int) {
        self.pid = pid
        self.ownerName = ownerName
        self.bounds = bounds
        self.layer = layer
    }
}

/// Maps windows to displays using public API only. No Accessibility attribute
/// reports a window's monitor, and the exact private method would make the app
/// un-notarizable, so this classifies by bounds overlap (PRD §6.5).
public enum GazeWindowClassifier {
    /// Windows smaller than this are panels, tooltips and status items.
    public static let minSide: CGFloat = 120

    /// The display holding at least `threshold` of the window's area, or nil
    /// for windows that straddle displays without a clear majority.
    public static func display(
        forWindowBounds bounds: CGRect,
        among displays: [GazeDisplay],
        threshold: Double = 0.5
    ) -> GazeDisplay? {
        let area = bounds.width * bounds.height
        guard area > 0 else { return nil }
        var best: (GazeDisplay, Double)?
        for display in displays {
            let overlap = bounds.intersection(display.bounds)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            let fraction = Double(overlap.width * overlap.height / area)
            guard fraction >= threshold else { continue }
            if best == nil || fraction > best!.1 { best = (display, fraction) }
        }
        return best?.0
    }

    /// Front-most ordinary window on a display. `windowsFrontToBack` must be in
    /// window-server z-order, which is what `CGWindowListCopyWindowInfo`
    /// returns. Only layer-0 windows count: menus, the menu bar and other
    /// system chrome sit on higher layers and are never a focus target.
    public static func frontmostWindow(
        on display: GazeDisplay,
        among windowsFrontToBack: [GazeWindow],
        excludingPID: Int32? = nil
    ) -> GazeWindow? {
        windowsFrontToBack.first { window in
            isCandidate(window, excludingPID: excludingPID)
                && self.display(forWindowBounds: window.bounds, among: [display]) != nil
        }
    }

    /// Which display currently holds the user's focus, taken as the display of
    /// the front-most ordinary window.
    public static func focusedDisplayKey(
        among windowsFrontToBack: [GazeWindow],
        displays: [GazeDisplay],
        excludingPID: Int32? = nil
    ) -> String? {
        for window in windowsFrontToBack where isCandidate(window, excludingPID: excludingPID) {
            if let display = display(forWindowBounds: window.bounds, among: displays) {
                return display.key
            }
        }
        return nil
    }

    private static func isCandidate(_ window: GazeWindow, excludingPID: Int32?) -> Bool {
        window.layer == 0
            && window.bounds.width >= minSide
            && window.bounds.height >= minSide
            && window.pid != excludingPID
    }
}
