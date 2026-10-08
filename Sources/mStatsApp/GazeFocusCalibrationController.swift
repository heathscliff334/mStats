import AppKit
import Observation
import SwiftUI
import mStatsKit

/// Walks the user through looking at five points on each display while the
/// capture engine records feature vectors, then hands the samples to the view
/// model to fit. Lives in the app target because it owns AppKit windows.
@MainActor
final class GazeFocusCalibrationController {
    private let viewModel: GazeFocusViewModel
    private let overlay = CalibrationOverlayModel()
    private var window: CalibrationWindow?
    private var task: Task<Void, Never>?

    /// Fractions of the display, in reading order. Corners plus centre cover
    /// the range of head turn the user will actually use.
    private static let points: [CGPoint] = [
        CGPoint(x: 0.12, y: 0.15), CGPoint(x: 0.88, y: 0.15), CGPoint(x: 0.5, y: 0.5),
        CGPoint(x: 0.12, y: 0.85), CGPoint(x: 0.88, y: 0.85),
    ]

    init(viewModel: GazeFocusViewModel) {
        self.viewModel = viewModel
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            await self?.run()
            self?.task = nil
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func run() async {
        let displays = GazeDisplayInventory.current()
        guard DisplayTopology.distinctDisplayCount(bounds: displays.map(\.bounds)) >= 2 else {
            alert("Calibration needs two displays", "Connect a second display (not mirrored) and try again.")
            return
        }
        guard await viewModel.beginCalibrationCapture() else {
            alert(
                "Camera access is needed",
                "Allow mStats to use the camera in System Settings → Privacy & Security → Camera, then try again."
            )
            return
        }
        defer {
            viewModel.endCalibrationCapture()
            closeOverlay()
        }

        NSApp.activate(ignoringOtherApps: true)
        var samples: [String: [GazeFeatureVector]] = [:]

        do {
            for (index, display) in displays.enumerated() {
                guard let screen = GazeDisplayInventory.screen(forKey: display.key) else { continue }
                show(on: screen)
                overlay.dot = nil
                overlay.title = "Display \(index + 1) of \(displays.count): \(display.name)"
                overlay.subtitle = "Sit as you normally would. Turn your head toward each dot and look at it."
                try await Task.sleep(for: .milliseconds(2200))

                for point in Self.points {
                    overlay.dot = point
                    overlay.isCollecting = false
                    try await Task.sleep(for: .milliseconds(700))
                    viewModel.startCollecting()
                    overlay.isCollecting = true
                    try await Task.sleep(for: .milliseconds(1000))
                    samples[display.key, default: []] += viewModel.stopCollecting()
                }
            }
        } catch {
            return
        }

        closeOverlay()
        if let message = viewModel.finishCalibration(samples: samples) {
            alert("Calibration didn't work", message)
        }
    }

    private func show(on screen: NSScreen) {
        closeOverlay()
        let window = CalibrationWindow(
            contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = NSColor.black.withAlphaComponent(0.92)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: CalibrationOverlayView(model: overlay))
        window.onEscape = { [weak self] in self?.cancel() }
        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private func closeOverlay() {
        window?.orderOut(nil)
        window = nil
    }

    private func alert(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

private final class CalibrationWindow: NSWindow {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
        } else {
            super.keyDown(with: event)
        }
    }
}

@Observable
@MainActor
private final class CalibrationOverlayModel {
    var title = ""
    var subtitle = ""
    var dot: CGPoint?
    var isCollecting = false
}

private struct CalibrationOverlayView: View {
    let model: CalibrationOverlayModel

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 10) {
                    Text(model.title).font(.system(size: 28, weight: .semibold))
                    Text(model.subtitle).font(.system(size: 16)).foregroundStyle(.white.opacity(0.7))
                    Text("Press Esc to cancel").font(.system(size: 13)).foregroundStyle(.white.opacity(0.4))
                        .padding(.top, 6)
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

                if let dot = model.dot {
                    Circle()
                        .fill(model.isCollecting ? Color.green : Color.white)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 6).scaleEffect(1.6))
                        .position(x: dot.x * proxy.size.width, y: dot.y * proxy.size.height)
                        .animation(.easeInOut(duration: 0.4), value: model.dot)
                        .animation(.easeInOut(duration: 0.15), value: model.isCollecting)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
