import Foundation

/// The mean feature vector observed while the user looked at one display.
public struct GazeDisplayProfile: Codable, Sendable, Equatable {
    public var key: String
    public var centroid: GazeFeatureVector
    public var sampleCount: Int
}

/// Persisted calibration. Tied to the Vision pipeline it was captured with:
/// landmark semantics differ by point count and revision, so a profile from a
/// different pipeline is discarded rather than trusted.
public struct GazeCalibrationProfile: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    public static let pipelinePointCount = 76
    public static let pipelineRevision = 3

    public var version: Int
    public var constellationPointCount: Int
    public var visionRevision: Int
    public var displays: [GazeDisplayProfile]
    /// Within-display spread of each feature, used to put the two features on
    /// one scale. Floored so a motionless calibration cannot divide by zero.
    public var yawSpread: Double
    public var pupilSpread: Double
    public var usesPupil: Bool
    /// Smallest pairwise distance between display centroids, in spread units.
    /// Roughly "how many noise-widths apart are the two closest displays".
    public var separation: Double
    public var createdAt: Date

    public var isCompatibleWithCurrentPipeline: Bool {
        version == Self.currentVersion
            && constellationPointCount == Self.pipelinePointCount
            && visionRevision == Self.pipelineRevision
    }

    public var displayKeys: Set<String> { Set(displays.map(\.key)) }
}

public enum GazeCalibrationError: Error, Equatable, Sendable {
    case tooFewDisplays
    case insufficientSamples(displayKey: String)
    case indistinguishable(separation: Double)
}

public enum GazeCalibrator {
    public static let minSamplesPerDisplay = 10
    /// Below this the displays cannot be told apart by the features at all
    /// (the user barely moved), so storing the profile would just make the
    /// feature switch randomly.
    public static let minSeparation = 0.5
    private static let spreadFloor = 1e-3
    private static let pupilCoverageRequired = 0.8

    public static func fit(
        samples: [String: [GazeFeatureVector]],
        now: Date = Date()
    ) throws -> GazeCalibrationProfile {
        guard samples.count >= 2 else { throw GazeCalibrationError.tooFewDisplays }
        for (key, group) in samples.sorted(by: { $0.key < $1.key }) where group.count < minSamplesPerDisplay {
            throw GazeCalibrationError.insufficientSamples(displayKey: key)
        }

        let keys = samples.keys.sorted()
        let all = keys.flatMap { samples[$0]! }
        let pupilCoverage = Double(all.filter(\.hasPupil).count) / Double(all.count)
        let usesPupil = pupilCoverage >= pupilCoverageRequired

        var profiles: [GazeDisplayProfile] = []
        var yawVariances: [Double] = []
        var pupilVariances: [Double] = []

        for key in keys {
            let group = samples[key]!
            let n = Double(group.count)
            let meanYaw = group.map(\.headYaw).reduce(0, +) / n
            let pupils = group.filter(\.hasPupil)
            let meanPupil = pupils.isEmpty ? 0 : pupils.map(\.pupilOffset).reduce(0, +) / Double(pupils.count)

            yawVariances.append(group.map { ($0.headYaw - meanYaw) * ($0.headYaw - meanYaw) }.reduce(0, +) / n)
            if !pupils.isEmpty {
                pupilVariances.append(
                    pupils.map { ($0.pupilOffset - meanPupil) * ($0.pupilOffset - meanPupil) }.reduce(0, +)
                        / Double(pupils.count)
                )
            }
            profiles.append(GazeDisplayProfile(
                key: key,
                centroid: GazeFeatureVector(headYaw: meanYaw, pupilOffset: meanPupil, hasPupil: !pupils.isEmpty),
                sampleCount: group.count
            ))
        }

        let yawSpread = max(spreadFloor, mean(yawVariances).squareRoot())
        let pupilSpread = max(spreadFloor, mean(pupilVariances).squareRoot())

        var profile = GazeCalibrationProfile(
            version: GazeCalibrationProfile.currentVersion,
            constellationPointCount: GazeCalibrationProfile.pipelinePointCount,
            visionRevision: GazeCalibrationProfile.pipelineRevision,
            displays: profiles,
            yawSpread: yawSpread,
            pupilSpread: pupilSpread,
            usesPupil: usesPupil,
            separation: 0,
            createdAt: now
        )

        var minDistance = Double.infinity
        for i in 0..<profiles.count {
            for j in (i + 1)..<profiles.count {
                minDistance = min(minDistance, distance(profiles[i].centroid, profiles[j].centroid, profile: profile))
            }
        }
        profile.separation = minDistance

        guard minDistance >= minSeparation else {
            throw GazeCalibrationError.indistinguishable(separation: minDistance)
        }
        return profile
    }

    /// Standardized distance: each feature divided by its calibrated spread so
    /// neither dominates by scale alone.
    static func distance(_ a: GazeFeatureVector, _ b: GazeFeatureVector, profile: GazeCalibrationProfile) -> Double {
        let dy = (a.headYaw - b.headYaw) / profile.yawSpread
        var sum = dy * dy
        if profile.usesPupil, a.hasPupil, b.hasPupil {
            let dp = (a.pupilOffset - b.pupilOffset) / profile.pupilSpread
            sum += dp * dp
        }
        return sum.squareRoot()
    }

    private static func mean(_ xs: [Double]) -> Double {
        xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count)
    }
}

public struct GazeClassification: Sendable, Equatable {
    public var displayKey: String
    /// 0 when equidistant from the two nearest displays, 1 when sitting on
    /// the centroid. A margin, not a probability.
    public var confidence: Double
}

public enum GazeMapper {
    /// Nearest-centroid classification in standardized feature space.
    public static func classify(_ vector: GazeFeatureVector, profile: GazeCalibrationProfile) -> GazeClassification? {
        guard profile.displays.count >= 2 else { return nil }
        let ranked = profile.displays
            .map { ($0.key, GazeCalibrator.distance(vector, $0.centroid, profile: profile)) }
            .sorted { $0.1 < $1.1 }
        let (nearestKey, d1) = ranked[0]
        let d2 = ranked[1].1
        guard d1 + d2 > 0 else { return nil }
        return GazeClassification(displayKey: nearestKey, confidence: (d2 - d1) / (d2 + d1))
    }
}
