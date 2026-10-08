import Testing
import CoreGraphics
import Foundation
@testable import mStatsKit

@Suite struct GazePausePolicyTests {
    private func reason(
        displays: Int = 2, locked: Bool = false, displaysAsleep: Bool = false, systemAsleep: Bool = false,
        lowPower: Bool = false, pauseOnLowPower: Bool = true, camera: Bool = false
    ) -> GazePauseReason? {
        GazePausePolicy.reason(
            distinctDisplayCount: displays, screenLocked: locked, displaysAsleep: displaysAsleep,
            systemAsleep: systemAsleep, lowPowerMode: lowPower, pauseOnLowPower: pauseOnLowPower,
            cameraInterrupted: camera
        )
    }

    @Test func runsWhenNothingIsWrong() { #expect(reason() == nil) }
    @Test func pausesWithASingleDisplay() { #expect(reason(displays: 1) == .singleDisplay) }
    @Test func pausesWhenLocked() { #expect(reason(locked: true) == .screenLocked) }
    @Test func pausesWhenDisplaysAsleep() { #expect(reason(displaysAsleep: true) == .displaysAsleep) }
    @Test func pausesWhenSystemAsleep() { #expect(reason(systemAsleep: true) == .systemAsleep) }
    @Test func pausesWhenCameraIsInterrupted() { #expect(reason(camera: true) == .cameraUnavailable) }

    @Test func lowPowerPauseIsConfigurable() {
        #expect(reason(lowPower: true, pauseOnLowPower: true) == .lowPowerMode)
        #expect(reason(lowPower: true, pauseOnLowPower: false) == nil)
    }

    @Test func mostFundamentalReasonWins() {
        #expect(reason(displays: 1, locked: true, systemAsleep: true) == .systemAsleep)
        #expect(reason(displays: 1, locked: true) == .screenLocked)
    }

    @Test func mirroredDisplaysCountAsOne() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        #expect(DisplayTopology.distinctDisplayCount(bounds: [frame, frame]) == 1)
    }

    @Test func separateDisplaysCountIndividually() {
        let a = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let b = CGRect(x: 1920, y: 0, width: 1920, height: 1080)
        #expect(DisplayTopology.distinctDisplayCount(bounds: [a, b]) == 2)
    }
}

@Suite struct GazeWindowClassifierTests {
    private let left = GazeDisplay(key: "L", name: "Left", bounds: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    private let right = GazeDisplay(key: "R", name: "Right", bounds: CGRect(x: 1920, y: 0, width: 1920, height: 1080))

    private func window(pid: Int32, x: CGFloat, w: CGFloat = 800, h: CGFloat = 600, layer: Int = 0) -> GazeWindow {
        GazeWindow(pid: pid, ownerName: "app\(pid)", bounds: CGRect(x: x, y: 100, width: w, height: h), layer: layer)
    }

    @Test func assignsToTheDisplayWithTheMajority() {
        #expect(GazeWindowClassifier.display(forWindowBounds: window(pid: 1, x: 100).bounds, among: [left, right])?.key == "L")
        #expect(GazeWindowClassifier.display(forWindowBounds: window(pid: 1, x: 2100).bounds, among: [left, right])?.key == "R")
    }

    @Test func straddlingWindowResolvesToTheLargerShare() {
        // 600 of 800pt on the left display.
        #expect(GazeWindowClassifier.display(forWindowBounds: window(pid: 1, x: 1320).bounds, among: [left, right])?.key == "L")
    }

    @Test func evenSplitBelowTheThresholdIsUnassigned() {
        let w = window(pid: 1, x: 1520)  // exactly 400/400
        #expect(GazeWindowClassifier.display(forWindowBounds: w.bounds, among: [left, right], threshold: 0.51) == nil)
    }

    @Test func picksTheFrontmostWindowOnTheTargetDisplay() {
        let windows = [window(pid: 1, x: 100), window(pid: 2, x: 2100), window(pid: 3, x: 2200)]
        #expect(GazeWindowClassifier.frontmostWindow(on: right, among: windows)?.pid == 2)
        #expect(GazeWindowClassifier.frontmostWindow(on: left, among: windows)?.pid == 1)
    }

    @Test func ignoresPanelsAndSystemChrome() {
        let windows = [
            window(pid: 1, x: 2100, layer: 25),
            window(pid: 2, x: 2100, w: 60, h: 40),
            window(pid: 3, x: 2100),
        ]
        #expect(GazeWindowClassifier.frontmostWindow(on: right, among: windows)?.pid == 3)
    }

    @Test func excludesOurOwnWindows() {
        let windows = [window(pid: 99, x: 2100), window(pid: 4, x: 2150)]
        #expect(GazeWindowClassifier.frontmostWindow(on: right, among: windows, excludingPID: 99)?.pid == 4)
    }

    @Test func noWindowOnADisplayYieldsNil() {
        #expect(GazeWindowClassifier.frontmostWindow(on: right, among: [window(pid: 1, x: 100)]) == nil)
    }

    @Test func focusedDisplayIsTheFrontmostWindowsDisplay() {
        let windows = [window(pid: 1, x: 2100), window(pid: 2, x: 100)]
        #expect(GazeWindowClassifier.focusedDisplayKey(among: windows, displays: [left, right]) == "R")
        #expect(GazeWindowClassifier.focusedDisplayKey(among: [], displays: [left, right]) == nil)
    }
}
