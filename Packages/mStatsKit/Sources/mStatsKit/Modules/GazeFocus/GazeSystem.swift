import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation

public enum GazePermission: String, Sendable, Equatable {
    case camera
    case accessibility

    public var title: String {
        switch self {
        case .camera: "Camera"
        case .accessibility: "Accessibility"
        }
    }

    public var settingsURL: URL {
        switch self {
        case .camera:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        }
    }
}

public enum GazePermissions {
    public static func accessibilityTrusted(prompt: Bool) -> Bool {
        // The literal key avoids reading the mutable-looking C global
        // `kAXTrustedCheckOptionPrompt`, which Swift 6 flags as non-Sendable.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": prompt] as CFDictionary)
    }

    public static func ensureCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }
}

public enum GazeInput {
    /// Time since the last key press anywhere in the session. Reads a system
    /// counter, so unlike an event monitor it needs no Input Monitoring grant.
    public static func secondsSinceKeyDown() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
    }

    public static func secondsSinceAnyInput() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}

@MainActor
public enum GazeDisplayInventory {
    /// Connected displays with mirrored duplicates collapsed, in CoreGraphics
    /// coordinates. Keyed by display UUID, which survives reboots and
    /// re-plugging (a `CGDirectDisplayID` does not).
    public static func current() -> [GazeDisplay] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)

        var seen: [CGRect] = []
        var result: [GazeDisplay] = []
        for id in ids.prefix(Int(count)) {
            let bounds = CGDisplayBounds(id)
            guard bounds.width > 0, bounds.height > 0, !seen.contains(bounds) else { continue }
            seen.append(bounds)
            result.append(GazeDisplay(
                key: key(for: id),
                name: name(for: id) ?? "Display \(result.count + 1)",
                bounds: bounds
            ))
        }
        return result
    }

    public static func displayID(forKey key: String) -> CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).first { self.key(for: $0) == key }
    }

    public static func screen(forKey key: String) -> NSScreen? {
        guard let id = displayID(forKey: key) else { return nil }
        return NSScreen.screens.first { $0.cgDirectDisplayID == id }
    }

    private static func key(for id: CGDirectDisplayID) -> String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return "display-\(id)"
    }

    private static func name(for id: CGDirectDisplayID) -> String? {
        NSScreen.screens.first { $0.cgDirectDisplayID == id }?.localizedName
    }
}

extension NSScreen {
    public var cgDirectDisplayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

public enum GazeWindowInventory {
    /// On-screen windows in window-server z-order, front to back. Bounds, owner
    /// and layer do not require Screen Recording (only window titles do).
    public static func windowsFrontToBack() -> [GazeWindow] {
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        return list.compactMap { entry in
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  let boundsDict = entry[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }
            return GazeWindow(
                pid: pid,
                ownerName: entry[kCGWindowOwnerName as String] as? String ?? "pid \(pid)",
                bounds: bounds,
                layer: entry[kCGWindowLayer as String] as? Int ?? 0
            )
        }
    }
}

public struct GazeFocusResult: Sendable, Equatable {
    public var succeeded: Bool
    public var detail: String
}

@MainActor
public enum GazeFocusActions {
    /// Brings `window`'s app forward, raises that specific window, and then
    /// *checks* that focus actually moved. An Accessibility call can report
    /// success while changing nothing, so the return value is never trusted.
    ///
    /// `NSRunningApplication.activate` is the call observed to move focus in the
    /// G0 spike; `kAXMain` returned unsupported on every app tested. The raise
    /// matters for apps with windows on both displays, where activating the app
    /// alone would leave its key window on the wrong one.
    public static func focus(window: GazeWindow, on display: GazeDisplay, movePointer: Bool) async -> GazeFocusResult {
        guard let app = NSRunningApplication(processIdentifier: window.pid) else {
            return GazeFocusResult(succeeded: false, detail: "\(window.ownerName) is no longer running")
        }

        _ = app.activate(options: [])
        raise(pid: window.pid, matching: window.bounds)
        if movePointer { warpPointer(to: display) }

        try? await Task.sleep(for: .milliseconds(250))

        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard front == window.pid else {
            return GazeFocusResult(succeeded: false, detail: "\(window.ownerName) did not become frontmost")
        }
        if let focused = focusedWindowBounds(pid: window.pid),
           GazeWindowClassifier.display(forWindowBounds: focused, among: [display]) == nil {
            return GazeFocusResult(succeeded: false, detail: "\(window.ownerName) focused a window on another display")
        }
        return GazeFocusResult(succeeded: true, detail: "Focused \(window.ownerName) on \(display.name)")
    }

    private static func warpPointer(to display: GazeDisplay) {
        CGWarpMouseCursorPosition(CGPoint(x: display.bounds.midX, y: display.bounds.midY))
        CGAssociateMouseAndMouseCursorPosition(1)
    }

    private static func raise(pid: pid_t, matching bounds: CGRect) {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return }
        for window in windows {
            guard let frame = frame(of: window), close(frame, bounds) else { continue }
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            return
        }
    }

    private static func focusedWindowBounds(pid: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return frame(of: value as! AXUIElement)
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return CGRect(origin: point, size: size)
    }

    private static func close(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 3) -> Bool {
        abs(a.origin.x - b.origin.x) <= tolerance
            && abs(a.origin.y - b.origin.y) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }
}
