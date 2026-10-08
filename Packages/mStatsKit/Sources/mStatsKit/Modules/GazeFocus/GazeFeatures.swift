import CoreGraphics
import Foundation

/// What the camera pipeline reduces one frame to. Kept deliberately small and
/// `Codable` so calibration can persist centroids of it directly.
///
/// Both features come from 2D landmark geometry in normalized face-box space,
/// which is distance-invariant: Vision on macOS 14 exposes no yaw/pitch/roll
/// (see PRD/gaze-focus.md §6.2), so head pose is derived, not read.
public struct GazeFeatureVector: Codable, Sendable, Equatable {
    /// Eye-midpoint minus nose x-offset. Tracks head rotation.
    public var headYaw: Double
    /// Pupil-midpoint x-offset from the face-box centre. Adds eye rotation on
    /// top of head rotation. Meaningless (0) when `hasPupil` is false.
    public var pupilOffset: Double
    public var hasPupil: Bool

    public init(headYaw: Double, pupilOffset: Double, hasPupil: Bool) {
        self.headYaw = headYaw
        self.pupilOffset = pupilOffset
        self.hasPupil = hasPupil
    }
}

public enum GazeFeatureExtractor {
    /// Landmark regions arrive as points in face-box normalized space
    /// (0...1, x to the right). Returns nil when the eyes or nose are missing,
    /// since without them there is no head-pose signal at all.
    public static func features(
        leftEye: [CGPoint],
        rightEye: [CGPoint],
        nose: [CGPoint],
        leftPupil: [CGPoint],
        rightPupil: [CGPoint]
    ) -> GazeFeatureVector? {
        guard let left = centroid(of: leftEye),
              let right = centroid(of: rightEye),
              let noseCentre = centroid(of: nose)
        else { return nil }

        let eyeMidX = Double((left.x + right.x) / 2)
        let yaw = eyeMidX - Double(noseCentre.x)

        if let lp = centroid(of: leftPupil), let rp = centroid(of: rightPupil) {
            let pupilMidX = Double((lp.x + rp.x) / 2)
            return GazeFeatureVector(headYaw: yaw, pupilOffset: pupilMidX - 0.5, hasPupil: true)
        }
        return GazeFeatureVector(headYaw: yaw, pupilOffset: 0, hasPupil: false)
    }

    public static func centroid(of points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for p in points {
            sumX += p.x
            sumY += p.y
        }
        let n = CGFloat(points.count)
        return CGPoint(x: sumX / n, y: sumY / n)
    }
}
