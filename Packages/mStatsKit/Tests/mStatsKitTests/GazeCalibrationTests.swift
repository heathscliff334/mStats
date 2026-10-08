import Testing
import CoreGraphics
import Foundation
@testable import mStatsKit

@Suite struct GazeFeatureExtractorTests {
    private func region(x: CGFloat) -> [CGPoint] { [CGPoint(x: x - 0.02, y: 0.5), CGPoint(x: x + 0.02, y: 0.5)] }

    @Test func yawIsEyeMidpointMinusNose() throws {
        let v = try #require(GazeFeatureExtractor.features(
            leftEye: region(x: 0.35), rightEye: region(x: 0.65), nose: region(x: 0.45),
            leftPupil: [], rightPupil: []
        ))
        #expect(abs(v.headYaw - (0.5 - 0.45)) < 1e-9)
        #expect(v.hasPupil == false)
        #expect(v.pupilOffset == 0)
    }

    @Test func pupilOffsetIsMeasuredFromFaceBoxCentre() throws {
        let v = try #require(GazeFeatureExtractor.features(
            leftEye: region(x: 0.35), rightEye: region(x: 0.65), nose: region(x: 0.5),
            leftPupil: [CGPoint(x: 0.40, y: 0.5)], rightPupil: [CGPoint(x: 0.70, y: 0.5)]
        ))
        #expect(v.hasPupil)
        #expect(abs(v.pupilOffset - 0.05) < 1e-9)
    }

    @Test func missingEyesOrNoseYieldsNoFeatures() {
        #expect(GazeFeatureExtractor.features(
            leftEye: [], rightEye: region(x: 0.65), nose: region(x: 0.5), leftPupil: [], rightPupil: []
        ) == nil)
        #expect(GazeFeatureExtractor.features(
            leftEye: region(x: 0.35), rightEye: region(x: 0.65), nose: [], leftPupil: [], rightPupil: []
        ) == nil)
    }
}

@Suite struct GazeCalibrationTests {
    /// Deterministic jitter so tests do not depend on a random generator.
    private func samples(yaw: Double, pupil: Double, count: Int = 20, hasPupil: Bool = true) -> [GazeFeatureVector] {
        (0..<count).map { i in
            let jitter = (Double(i % 5) - 2) * 0.002
            return GazeFeatureVector(headYaw: yaw + jitter, pupilOffset: hasPupil ? pupil + jitter : 0, hasPupil: hasPupil)
        }
    }

    private func twoDisplayProfile() throws -> GazeCalibrationProfile {
        try GazeCalibrator.fit(samples: [
            "left": samples(yaw: -0.04, pupil: -0.03),
            "right": samples(yaw: 0.04, pupil: 0.03),
        ])
    }

    @Test func fitProducesCentroidsPerDisplay() throws {
        let profile = try twoDisplayProfile()
        #expect(profile.displayKeys == ["left", "right"])
        #expect(profile.isCompatibleWithCurrentPipeline)
        #expect(profile.usesPupil)
        #expect(profile.separation > GazeCalibrator.minSeparation)
    }

    @Test func classifiesTowardTheNearestDisplay() throws {
        let profile = try twoDisplayProfile()
        let left = GazeMapper.classify(GazeFeatureVector(headYaw: -0.035, pupilOffset: -0.025, hasPupil: true), profile: profile)
        let right = GazeMapper.classify(GazeFeatureVector(headYaw: 0.045, pupilOffset: 0.03, hasPupil: true), profile: profile)
        #expect(left?.displayKey == "left")
        #expect(right?.displayKey == "right")
        #expect((left?.confidence ?? 0) > 0.5)
    }

    @Test func midpointHasNearZeroConfidence() throws {
        let profile = try twoDisplayProfile()
        let mid = GazeMapper.classify(GazeFeatureVector(headYaw: 0, pupilOffset: 0, hasPupil: true), profile: profile)
        #expect((mid?.confidence ?? 1) < 0.05)
    }

    @Test func worksWithoutPupilData() throws {
        let profile = try GazeCalibrator.fit(samples: [
            "a": samples(yaw: -0.05, pupil: 0, hasPupil: false),
            "b": samples(yaw: 0.05, pupil: 0, hasPupil: false),
        ])
        #expect(profile.usesPupil == false)
        let hit = GazeMapper.classify(GazeFeatureVector(headYaw: 0.05, pupilOffset: 0, hasPupil: false), profile: profile)
        #expect(hit?.displayKey == "b")
    }

    @Test func supportsThreeDisplays() throws {
        let profile = try GazeCalibrator.fit(samples: [
            "l": samples(yaw: -0.08, pupil: -0.05),
            "c": samples(yaw: 0.0, pupil: 0.0),
            "r": samples(yaw: 0.08, pupil: 0.05),
        ])
        let hit = GazeMapper.classify(GazeFeatureVector(headYaw: 0.0, pupilOffset: 0.0, hasPupil: true), profile: profile)
        #expect(hit?.displayKey == "c")
    }

    @Test func rejectsASingleDisplay() {
        #expect(throws: GazeCalibrationError.tooFewDisplays) {
            try GazeCalibrator.fit(samples: ["only": samples(yaw: 0, pupil: 0)])
        }
    }

    @Test func rejectsTooFewSamples() {
        #expect(throws: GazeCalibrationError.insufficientSamples(displayKey: "b")) {
            try GazeCalibrator.fit(samples: [
                "a": samples(yaw: -0.05, pupil: -0.03),
                "b": samples(yaw: 0.05, pupil: 0.03, count: 3),
            ])
        }
    }

    @Test func rejectsDisplaysTheUserNeverDistinguished() {
        // Head did not move between the two displays: identical centroids.
        #expect(throws: (any Error).self) {
            try GazeCalibrator.fit(samples: [
                "a": samples(yaw: 0.01, pupil: 0.01),
                "b": samples(yaw: 0.01, pupil: 0.01),
            ])
        }
    }

    @Test func profileSurvivesJSONRoundTrip() throws {
        let profile = try twoDisplayProfile()
        let decoded = try JSONDecoder().decode(GazeCalibrationProfile.self, from: JSONEncoder().encode(profile))
        #expect(decoded == profile)
    }

    @Test func profileFromAnotherPipelineIsIncompatible() throws {
        var profile = try twoDisplayProfile()
        profile.visionRevision = 2
        #expect(profile.isCompatibleWithCurrentPipeline == false)
        profile.visionRevision = GazeCalibrationProfile.pipelineRevision
        profile.constellationPointCount = 65
        #expect(profile.isCompatibleWithCurrentPipeline == false)
    }
}
