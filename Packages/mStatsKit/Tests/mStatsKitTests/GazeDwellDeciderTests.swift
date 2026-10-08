import Testing
import Foundation
@testable import mStatsKit

/// Frames arrive every ~100-125ms in practice (5-10 fps), so these tests feed
/// observations at that cadence rather than jumping straight to a timestamp.
@Suite struct GazeDwellDeciderTests {
    private let idle: TimeInterval = 100

    private struct Fire: Equatable {
        var time: Double
        var target: String
    }

    /// Feeds `target` once per `step` from `from` up to (not including) `to`.
    private func feed(
        _ d: inout GazeDwellDecider,
        _ target: String?,
        from: Double,
        to: Double,
        step: Double = 0.1,
        sinceKey: Double = 100,
        suppressed: Bool = false
    ) -> [Fire] {
        var fires: [Fire] = []
        var i = 0
        while true {
            let t = from + Double(i) * step
            if t >= to - 1e-9 { break }
            if let hit = d.observe(target: target, now: t, secondsSinceKeyDown: sinceKey, suppressed: suppressed) {
                fires.append(Fire(time: t, target: hit))
            }
            i += 1
        }
        return fires
    }

    @Test func firesOnlyAfterTheDwellTime() {
        var d = GazeDwellDecider(dwell: 0.3)
        let fires = feed(&d, "B", from: 0, to: 1.0)
        #expect(fires.count == 1)
        #expect(fires.first!.target == "B")
        #expect(fires.first!.time >= 0.3 - 1e-9)
        #expect(fires.first!.time < 0.45)
    }

    @Test func doesNotFireBeforeTheDwellElapses() {
        var d = GazeDwellDecider(dwell: 0.3)
        #expect(feed(&d, "B", from: 0, to: 0.25).isEmpty)
    }

    @Test func firesOncePerVisit() {
        var d = GazeDwellDecider(dwell: 0.3)
        #expect(feed(&d, "B", from: 0, to: 10).count == 1)
    }

    @Test func aSingleMissedFrameDoesNotRefire() {
        var d = GazeDwellDecider(dwell: 0.3)
        var fires = feed(&d, "B", from: 0, to: 1.0)
        fires += feed(&d, nil, from: 1.0, to: 1.1)
        fires += feed(&d, "B", from: 1.1, to: 4.0)
        #expect(fires.count == 1)
    }

    @Test func toleratesTwoMissedFramesAt8fps() {
        var d = GazeDwellDecider()
        var fires = feed(&d, "B", from: 0, to: 1.0, step: 0.125)
        fires += feed(&d, nil, from: 1.0, to: 1.25, step: 0.125)
        fires += feed(&d, "B", from: 1.25, to: 4.0, step: 0.125)
        #expect(fires.count == 1)
    }

    @Test func aSingleWrongFrameDoesNotRefire() {
        var d = GazeDwellDecider(dwell: 0.3)
        var fires = feed(&d, "B", from: 0, to: 1.0)
        fires += feed(&d, "A", from: 1.0, to: 1.1)
        fires += feed(&d, "B", from: 1.1, to: 4.0)
        #expect(fires == [Fire(time: fires[0].time, target: "B")])
    }

    @Test func aSingleWrongFrameDoesNotCancelADwell() {
        var d = GazeDwellDecider(dwell: 0.3)
        var fires = feed(&d, "B", from: 0, to: 0.2)
        fires += feed(&d, "A", from: 0.2, to: 0.3)
        fires += feed(&d, "B", from: 0.3, to: 1.0)
        #expect(fires.count == 1)
        #expect(fires.first?.target == "B")
        #expect(fires.first!.time < 0.45)
    }

    @Test func aSustainedChangeOfTargetTakesOver() {
        var d = GazeDwellDecider(dwell: 0.3)
        var fires = feed(&d, "B", from: 0, to: 0.2)
        fires += feed(&d, "A", from: 0.2, to: 2.0)
        #expect(fires.map(\.target) == ["A"])
    }

    @Test func movingBetweenDisplaysSwitchesEachTime() {
        var d = GazeDwellDecider(dwell: 0.3)
        var fires = feed(&d, "B", from: 0, to: 1.0)
        fires += feed(&d, "A", from: 1.0, to: 2.0)
        fires += feed(&d, "B", from: 2.0, to: 3.0)
        #expect(fires.map(\.target) == ["B", "A", "B"])
    }

    @Test func lookingAwayAndBackAllowsAFreshSwitch() {
        var d = GazeDwellDecider(dwell: 0.3)
        var fires = feed(&d, "B", from: 0, to: 1.0)
        fires += feed(&d, nil, from: 1.0, to: 2.0)
        fires += feed(&d, "B", from: 2.0, to: 3.0)
        #expect(fires.map(\.target) == ["B", "B"])
    }

    @Test func neverFiresWhileTyping() {
        var d = GazeDwellDecider(dwell: 0.3, typingGuard: 1.0)
        #expect(feed(&d, "B", from: 0, to: 5.0, sinceKey: 0.2).isEmpty)
    }

    @Test func dwellRestartsAfterTypingEnds() {
        var d = GazeDwellDecider(dwell: 0.3, typingGuard: 1.0)
        _ = feed(&d, "B", from: 0, to: 2.0, sinceKey: 0.2)
        let fires = feed(&d, "B", from: 2.0, to: 3.0)
        #expect(fires.count == 1)
        // Looking during typing must not count toward the dwell.
        #expect(fires.first!.time >= 2.3 - 1e-9)
    }

    @Test func suppressionBlocksSwitchingAndDropsTheCandidate() {
        var d = GazeDwellDecider(dwell: 0.3)
        #expect(feed(&d, "B", from: 0, to: 2.0, suppressed: true).isEmpty)
        let fires = feed(&d, "B", from: 2.0, to: 3.0)
        #expect(fires.count == 1)
        #expect(fires.first!.time >= 2.3 - 1e-9)
    }

    @Test func noTargetNeverFires() {
        var d = GazeDwellDecider()
        #expect(feed(&d, nil, from: 0, to: 5).isEmpty)
    }

    @Test func resetForgetsTheFiredVisit() {
        var d = GazeDwellDecider(dwell: 0.3)
        #expect(feed(&d, "B", from: 0, to: 1.0).count == 1)
        d.reset()
        #expect(feed(&d, "B", from: 1.0, to: 2.0).count == 1)
    }
}
