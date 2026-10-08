import AppKit
import CoreGraphics
import Foundation
import Observation

public enum GazeFocusState: Sendable, Equatable {
    case off
    case starting
    case active
    case paused(GazePauseReason)
    case needsPermission(GazePermission)
    case needsCalibration
    case calibrating

    public var label: String {
        switch self {
        case .off: "Off"
        case .starting: "Starting…"
        case .active: "Active"
        case .paused(let reason): "Paused — \(reason.message)"
        case .needsPermission(let permission): "Needs \(permission.title) access"
        case .needsCalibration: "Needs calibration"
        case .calibrating: "Calibrating…"
        }
    }
}

public struct GazeSwitchRecord: Sendable, Equatable {
    public var date: Date
    public var succeeded: Bool
    public var detail: String
}

public struct GazeFocusSnapshot: Sendable, Equatable {
    public var state: GazeFocusState = .off
    /// Display the user is currently judged to be looking at, when confident.
    public var lookingAtKey: String?
    public var confidence: Double = 0
    public var lastSwitch: GazeSwitchRecord?
}

public struct GazeCalibrationSummary: Sendable, Equatable {
    public var displayCount: Int
    public var separation: Double
    public var createdAt: Date

    /// Plain-language read of how well the displays were told apart.
    public var quality: String {
        switch separation {
        case 3...: "Excellent"
        case 1.5..<3: "Good"
        default: "Weak — turn your head more when recalibrating"
        }
    }
}

/// Bridges the capture engine to the rest of the app. Like every module view
/// model, `start()` and `stop()` are idempotent and cheap to call every
/// `reconcile()` tick — and, unlike a poll loop, they must never block: all
/// camera and Vision work lives on `GazeCaptureEngine`'s own queues.
@Observable
@MainActor
public final class GazeFocusViewModel {
    public private(set) var snapshot = GazeFocusSnapshot()
    /// Set when enabling failed for lack of a permission. The toggle is turned
    /// back off, so this is what lets the UI explain why.
    public private(set) var permissionIssue: GazePermission?
    public private(set) var calibrationSummary: GazeCalibrationSummary?
    public private(set) var calibrationMessage: String?
    public private(set) var displays: [GazeDisplay] = []

    /// Set by the app target, which owns the overlay windows calibration needs.
    public var onCalibrationRequested: (() -> Void)?

    private let settings: AppSettings
    private let logger = MetricLog.logger("GazeFocus")
    private var engine: GazeCaptureEngine?
    private var profile: GazeCalibrationProfile?
    private var decider = GazeDwellDecider()

    private var started = false
    private var bringUpComplete = false
    private var calibrating = false
    private var collecting = false
    private var collectionBuffer: [GazeFeatureVector] = []
    private var engineRunning = false
    private var focusInFlight = false

    private var screenLocked = false
    private var displaysAsleep = false
    private var systemAsleep = false
    private var cameraInterrupted = false
    private var spaceSettleUntil: TimeInterval = 0
    private var lowFPS = false

    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var retryTask: Task<Void, Never>?

    public init(settings: AppSettings) {
        self.settings = settings
        loadProfile()
    }

    // MARK: - Lifecycle (called from reconcile())

    public func start() {
        guard !started else { return }
        started = true
        permissionIssue = nil
        bringUpComplete = false
        refreshSystemState()
        installObservers()
        snapshot.state = .starting
        Task { await bringUp() }
    }

    public func stop() {
        guard started else { return }
        started = false
        bringUpComplete = false
        retryTask?.cancel()
        retryTask = nil
        removeObservers()
        decider.reset()
        applyEngine(wanted: calibrating)
        snapshot.lookingAtKey = nil
        snapshot.confidence = 0
        snapshot.state = calibrating ? .calibrating : (permissionIssue.map { .needsPermission($0) } ?? .off)
    }

    private func bringUp() async {
        guard await GazePermissions.ensureCameraAccess() else { deny(.camera); return }
        guard started else { return }
        guard GazePermissions.accessibilityTrusted(prompt: true) else { deny(.accessibility); return }
        guard started else { return }

        bringUpComplete = true
        let needsCalibration = !hasUsableProfile
        evaluate()
        if needsCalibration, !calibrating { onCalibrationRequested?() }
    }

    /// Turns the feature back off and records why, so the toggle never claims
    /// to be on while nothing can run.
    private func deny(_ permission: GazePermission) {
        guard started else { return }
        permissionIssue = permission
        snapshot.state = .needsPermission(permission)
        settings.gazeFocusEnabled = false
    }

    // MARK: - Calibration

    public func requestCalibration() {
        onCalibrationRequested?()
    }

    public func resetCalibration() {
        profile = nil
        settings.gazeFocusCalibrationData = nil
        calibrationSummary = nil
        calibrationMessage = nil
        decider.reset()
        evaluate()
    }

    /// Brings the camera up for a calibration run, even if the feature itself
    /// is switched off. Returns false if the camera permission is missing.
    public func beginCalibrationCapture() async -> Bool {
        guard !calibrating else { return false }
        permissionIssue = nil
        guard await GazePermissions.ensureCameraAccess() else {
            permissionIssue = .camera
            return false
        }
        calibrating = true
        collecting = false
        evaluate()
        return true
    }

    public func startCollecting() {
        collectionBuffer.removeAll(keepingCapacity: true)
        collecting = true
    }

    public func stopCollecting() -> [GazeFeatureVector] {
        collecting = false
        defer { collectionBuffer.removeAll(keepingCapacity: true) }
        return collectionBuffer
    }

    public func endCalibrationCapture() {
        calibrating = false
        collecting = false
        collectionBuffer.removeAll(keepingCapacity: true)
        evaluate()
    }

    /// Fits and stores a calibration. Returns a user-facing error message on
    /// failure, nil on success.
    @discardableResult
    public func finishCalibration(samples: [String: [GazeFeatureVector]]) -> String? {
        do {
            let fitted = try GazeCalibrator.fit(samples: samples)
            profile = fitted
            settings.gazeFocusCalibrationData = try JSONEncoder().encode(fitted)
            calibrationMessage = nil
            decider.reset()
            publishSummary()
            evaluate()
            return nil
        } catch GazeCalibrationError.tooFewDisplays {
            return fail("Calibration needs at least two displays.")
        } catch GazeCalibrationError.insufficientSamples {
            return fail("Couldn't see your face for long enough. Check the lighting and try again.")
        } catch GazeCalibrationError.indistinguishable {
            return fail("Couldn't tell your displays apart. Turn your head toward each display when calibrating.")
        } catch {
            return fail("Calibration failed: \(error.localizedDescription)")
        }
    }

    private func fail(_ message: String) -> String {
        calibrationMessage = message
        return message
    }

    public func displayName(for key: String) -> String {
        displays.first { $0.key == key }?.name ?? "another display"
    }

    // MARK: - State evaluation

    private var hasUsableProfile: Bool {
        profile?.isCompatibleWithCurrentPipeline == true
    }

    private func evaluate() {
        let current = GazeDisplayInventory.current()
        if current != displays { displays = current }

        if calibrating {
            // A lost camera must not be restarted here: that would spin in a
            // tight fail/restart loop. The retry task owns recovery.
            if cameraInterrupted {
                applyEngine(wanted: false)
                snapshot.state = .paused(.cameraUnavailable)
            } else {
                applyEngine(wanted: true)
                snapshot.state = .calibrating
            }
            return
        }
        guard started else {
            applyEngine(wanted: false)
            snapshot.lookingAtKey = nil
            snapshot.state = permissionIssue.map { .needsPermission($0) } ?? .off
            return
        }
        guard bringUpComplete else {
            snapshot.state = .starting
            return
        }

        if let reason = GazePausePolicy.reason(
            distinctDisplayCount: DisplayTopology.distinctDisplayCount(bounds: displays.map(\.bounds)),
            screenLocked: screenLocked,
            displaysAsleep: displaysAsleep,
            systemAsleep: systemAsleep,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            pauseOnLowPower: settings.gazeFocusPauseOnLowPower,
            cameraInterrupted: cameraInterrupted
        ) {
            applyEngine(wanted: false)
            snapshot.state = .paused(reason)
            snapshot.lookingAtKey = nil
            return
        }

        guard let profile, hasUsableProfile else {
            applyEngine(wanted: false)
            snapshot.state = .needsCalibration
            return
        }
        if profile.displayKeys != Set(displays.map(\.key)) {
            calibrationMessage = "Your display setup changed since calibration. Recalibrate to continue."
            applyEngine(wanted: false)
            snapshot.state = .needsCalibration
            return
        }

        calibrationMessage = nil
        applyEngine(wanted: true)
        snapshot.state = .active
    }

    private func applyEngine(wanted: Bool) {
        guard wanted != engineRunning else { return }
        engineRunning = wanted
        if wanted {
            lowFPS = false
            let engine = self.engine ?? makeEngine()
            engine.setTargetFPS(GazeCaptureEngine.defaultFPS)
            engine.start()
        } else {
            engine?.stop()
            decider.reset()
        }
    }

    private func makeEngine() -> GazeCaptureEngine {
        let engine = GazeCaptureEngine { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        self.engine = engine
        return engine
    }

    // MARK: - Frames

    private func handle(_ event: GazeCaptureEngine.Event) {
        guard engineRunning else { return }
        switch event {
        case .frame(let features):
            handle(features: features)
        case .interrupted:
            markCameraLost("Camera disconnected")
        case .failed(let message):
            markCameraLost(message)
        }
    }

    private func markCameraLost(_ message: String) {
        logger.error("Camera lost: \(message, privacy: .public)")
        cameraInterrupted = true
        engineRunning = false
        evaluate()
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            self.cameraInterrupted = false
            self.evaluate()
        }
    }

    private func handle(features: GazeFeatureVector?) {
        if collecting, let features { collectionBuffer.append(features) }
        guard snapshot.state == .active, let profile else { return }

        adaptFrameRate()

        let classification = features.flatMap { GazeMapper.classify($0, profile: profile) }
        let confident = classification.flatMap { $0.confidence >= settings.gazeFocusMinConfidence ? $0 : nil }

        let confidence = ((classification?.confidence ?? 0) * 100).rounded() / 100
        if snapshot.lookingAtKey != confident?.displayKey { snapshot.lookingAtKey = confident?.displayKey }
        if snapshot.confidence != confidence { snapshot.confidence = confidence }

        decider.dwell = settings.gazeFocusDwellMs / 1000
        decider.typingGuard = settings.gazeFocusTypingGuardMs / 1000
        let now = ProcessInfo.processInfo.systemUptime
        if let target = decider.observe(
            target: confident?.displayKey,
            now: now,
            secondsSinceKeyDown: GazeInput.secondsSinceKeyDown(),
            suppressed: now < spaceSettleUntil
        ) {
            perform(switchTo: target)
        }
    }

    /// Drops to ~2 fps while the user is away from the keyboard and mouse, and
    /// back to full rate on the first frame after they return.
    private func adaptFrameRate() {
        let idle = GazeInput.secondsSinceAnyInput() > 30
        guard idle != lowFPS else { return }
        lowFPS = idle
        engine?.setTargetFPS(idle ? 2 : GazeCaptureEngine.defaultFPS)
    }

    private func perform(switchTo key: String) {
        guard !focusInFlight else { return }
        let all = GazeDisplayInventory.current()
        guard let display = all.first(where: { $0.key == key }) else { return }

        let windows = GazeWindowInventory.windowsFrontToBack()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if GazeWindowClassifier.focusedDisplayKey(among: windows, displays: all, excludingPID: ownPID) == key {
            return
        }
        guard let window = GazeWindowClassifier.frontmostWindow(on: display, among: windows, excludingPID: ownPID) else {
            record(GazeFocusResult(succeeded: false, detail: "No window to focus on \(display.name)"))
            return
        }

        focusInFlight = true
        let movePointer = settings.gazeFocusMovePointer
        Task {
            let result = await GazeFocusActions.focus(window: window, on: display, movePointer: movePointer)
            record(result)
            focusInFlight = false
        }
    }

    private func record(_ result: GazeFocusResult) {
        logger.debug("switch: \(result.detail, privacy: .public) ok=\(result.succeeded, privacy: .public)")
        snapshot.lastSwitch = GazeSwitchRecord(date: Date(), succeeded: result.succeeded, detail: result.detail)
    }

    // MARK: - System state

    private func loadProfile() {
        guard let data = settings.gazeFocusCalibrationData,
              let decoded = try? JSONDecoder().decode(GazeCalibrationProfile.self, from: data),
              decoded.isCompatibleWithCurrentPipeline
        else {
            profile = nil
            calibrationSummary = nil
            return
        }
        profile = decoded
        publishSummary()
    }

    private func publishSummary() {
        guard let profile else { calibrationSummary = nil; return }
        calibrationSummary = GazeCalibrationSummary(
            displayCount: profile.displays.count,
            separation: profile.separation,
            createdAt: profile.createdAt
        )
    }

    private func refreshSystemState() {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        screenLocked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
        displaysAsleep = false
        systemAsleep = false
        cameraInterrupted = false
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let center = NotificationCenter.default
        let distributed = DistributedNotificationCenter.default()

        func add(_ nc: NotificationCenter, _ name: Notification.Name, _ change: @escaping @MainActor (GazeFocusViewModel) -> Void) {
            let token = nc.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    change(self)
                    self.evaluate()
                }
            }
            observers.append((nc, token))
        }

        add(workspace, NSWorkspace.screensDidSleepNotification) { $0.displaysAsleep = true }
        add(workspace, NSWorkspace.screensDidWakeNotification) { $0.displaysAsleep = false }
        add(workspace, NSWorkspace.willSleepNotification) { $0.systemAsleep = true }
        add(workspace, NSWorkspace.didWakeNotification) { $0.systemAsleep = false; $0.displaysAsleep = false }
        // A Space switch animates for a moment; acting mid-transition produces
        // a visibly wrong result, so hold off briefly afterwards.
        add(workspace, NSWorkspace.activeSpaceDidChangeNotification) {
            $0.spaceSettleUntil = ProcessInfo.processInfo.systemUptime + 1.0
        }
        add(center, NSApplication.didChangeScreenParametersNotification) { _ in }
        add(center, .NSProcessInfoPowerStateDidChange) { _ in }
        add(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true }
        add(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.screenLocked = false }
    }

    private func removeObservers() {
        for (center, token) in observers { center.removeObserver(token) }
        observers.removeAll()
    }
}
