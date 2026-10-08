import Foundation

/// Decides *when* a sustained look becomes a focus switch. Pure and
/// time-injected so it can be tested without a camera or a clock.
///
/// A switch fires at most once per "visit": after firing for a display it will
/// not fire for that display again until the gaze has left it for longer than
/// `gapTolerance`. That keeps it from fighting the user when they click back to
/// the other display while still looking at the first one.
public struct GazeDwellDecider: Sendable {
    public var dwell: TimeInterval
    public var typingGuard: TimeInterval
    /// How long a missing or disagreeing observation is tolerated before a
    /// candidate or fired visit is considered over. Absorbs single noisy frames
    /// at 5-10 fps.
    public var gapTolerance: TimeInterval

    private var candidate: String?
    private var candidateSince: TimeInterval = 0
    private var candidateLastSeen: TimeInterval = 0
    /// A different display seen while a candidate is still fresh. It only
    /// replaces the candidate once it has itself persisted past `gapTolerance`,
    /// so one misclassified frame cannot derail an in-progress dwell.
    private var challenger: String?
    private var challengerSince: TimeInterval = 0
    private var challengerLastSeen: TimeInterval = 0
    private var firedTarget: String?
    private var firedLastSeen: TimeInterval = 0

    /// The default tolerance covers two consecutive missed frames at 8 fps
    /// (a 0.375 s gap between sightings).
    public init(dwell: TimeInterval = 0.3, typingGuard: TimeInterval = 1.0, gapTolerance: TimeInterval = 0.4) {
        self.dwell = dwell
        self.typingGuard = typingGuard
        self.gapTolerance = gapTolerance
    }

    public mutating func reset() {
        candidate = nil
        challenger = nil
        firedTarget = nil
    }

    /// - Parameters:
    ///   - target: display currently classified as the gaze target, or nil when
    ///     there is no face or the classification is not confident.
    ///   - now: monotonic seconds.
    ///   - secondsSinceKeyDown: time since the last key press anywhere.
    ///   - suppressed: true during moments when acting would be wrong (Space
    ///     transitions). Drops any pending candidate.
    /// - Returns: the display to switch to, when one should fire now.
    public mutating func observe(
        target: String?,
        now: TimeInterval,
        secondsSinceKeyDown: TimeInterval,
        suppressed: Bool = false
    ) -> String? {
        if suppressed || secondsSinceKeyDown < typingGuard {
            candidate = nil
            challenger = nil
            if let target, target == firedTarget { firedLastSeen = now }
            return nil
        }

        if firedTarget != nil, now - firedLastSeen > gapTolerance { firedTarget = nil }
        if candidate != nil, now - candidateLastSeen > gapTolerance {
            if let waiting = challenger, now - challengerLastSeen <= gapTolerance {
                candidate = waiting
                candidateSince = challengerSince
                candidateLastSeen = challengerLastSeen
            } else {
                candidate = nil
            }
            challenger = nil
        }

        guard let target else { return nil }

        if target == firedTarget {
            firedLastSeen = now
            return nil
        }

        if target == candidate {
            candidateLastSeen = now
            challenger = nil
            if now - candidateSince >= dwell {
                firedTarget = target
                firedLastSeen = now
                candidate = nil
                return target
            }
            return nil
        }

        guard candidate != nil else {
            candidate = target
            candidateSince = now
            candidateLastSeen = now
            return nil
        }

        if challenger == target {
            challengerLastSeen = now
            if now - challengerSince > gapTolerance {
                candidate = target
                candidateSince = challengerSince
                candidateLastSeen = now
                challenger = nil
            }
        } else {
            challenger = target
            challengerSince = now
            challengerLastSeen = now
        }
        return nil
    }
}
