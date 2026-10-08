import Testing
import Foundation
@testable import mStatsKit

/// Covers the parts of the view model that never touch the camera. Nothing
/// here calls `start()`, so no capture session or permission prompt can occur.
@MainActor
@Suite struct GazeFocusViewModelTests {
    private func settings() -> AppSettings {
        let name = "com.hartono.mStatsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return AppSettings(defaults: defaults)
    }

    private func samples(yaw: Double, count: Int = 20) -> [GazeFeatureVector] {
        (0..<count).map { i in
            let j = (Double(i % 5) - 2) * 0.002
            return GazeFeatureVector(headYaw: yaw + j, pupilOffset: yaw * 0.7 + j, hasPupil: true)
        }
    }

    private func validProfileData() throws -> Data {
        let profile = try GazeCalibrator.fit(samples: ["a": samples(yaw: -0.05), "b": samples(yaw: 0.05)])
        return try JSONEncoder().encode(profile)
    }

    @Test func startsOffAndUncalibrated() {
        let vm = GazeFocusViewModel(settings: settings())
        #expect(vm.snapshot.state == .off)
        #expect(vm.calibrationSummary == nil)
        #expect(vm.permissionIssue == nil)
    }

    @Test func stopWithoutStartIsANoOp() {
        let vm = GazeFocusViewModel(settings: settings())
        vm.stop()
        vm.stop()
        #expect(vm.snapshot.state == .off)
    }

    @Test func loadsAStoredCalibration() throws {
        let s = settings()
        s.gazeFocusCalibrationData = try validProfileData()
        let vm = GazeFocusViewModel(settings: s)
        #expect(vm.calibrationSummary?.displayCount == 2)
    }

    @Test func discardsACalibrationFromAnotherPipeline() throws {
        let s = settings()
        var profile = try JSONDecoder().decode(GazeCalibrationProfile.self, from: validProfileData())
        profile.visionRevision = 2
        s.gazeFocusCalibrationData = try JSONEncoder().encode(profile)
        let vm = GazeFocusViewModel(settings: s)
        #expect(vm.calibrationSummary == nil)
    }

    @Test func ignoresCorruptCalibrationData() {
        let s = settings()
        s.gazeFocusCalibrationData = Data("not json".utf8)
        #expect(GazeFocusViewModel(settings: s).calibrationSummary == nil)
    }

    @Test func resetClearsStoredCalibration() throws {
        let s = settings()
        s.gazeFocusCalibrationData = try validProfileData()
        let vm = GazeFocusViewModel(settings: s)
        vm.resetCalibration()
        #expect(vm.calibrationSummary == nil)
        #expect(s.gazeFocusCalibrationData == nil)
    }

    @Test func successfulCalibrationIsStoredAndSummarised() {
        let s = settings()
        let vm = GazeFocusViewModel(settings: s)
        let error = vm.finishCalibration(samples: ["a": samples(yaw: -0.05), "b": samples(yaw: 0.05)])
        #expect(error == nil)
        #expect(vm.calibrationSummary?.displayCount == 2)
        #expect(s.gazeFocusCalibrationData != nil)
    }

    @Test func failedCalibrationIsNotStoredAndExplainsWhy() {
        let s = settings()
        let vm = GazeFocusViewModel(settings: s)
        let error = vm.finishCalibration(samples: ["a": samples(yaw: 0.01), "b": samples(yaw: 0.01)])
        #expect(error != nil)
        #expect(vm.calibrationSummary == nil)
        #expect(s.gazeFocusCalibrationData == nil)
        #expect(vm.calibrationMessage == error)
    }

    @Test func tooFewSamplesGivesAFriendlyMessage() {
        let vm = GazeFocusViewModel(settings: settings())
        let error = vm.finishCalibration(samples: ["a": samples(yaw: -0.05, count: 2), "b": samples(yaw: 0.05)])
        #expect(error?.contains("face") == true)
    }

    @Test func collectingBuffersOnlyBetweenStartAndStop() {
        let vm = GazeFocusViewModel(settings: settings())
        #expect(vm.stopCollecting().isEmpty)
        vm.startCollecting()
        #expect(vm.stopCollecting().isEmpty)
    }

    @Test func calibrationQualityReadsInPlainLanguage() {
        func quality(_ sep: Double) -> String {
            GazeCalibrationSummary(displayCount: 2, separation: sep, createdAt: Date()).quality
        }
        #expect(quality(4) == "Excellent")
        #expect(quality(2) == "Good")
        #expect(quality(0.8).hasPrefix("Weak"))
    }

    @Test func stateLabelsAreHumanReadable() {
        #expect(GazeFocusState.off.label == "Off")
        #expect(GazeFocusState.active.label == "Active")
        #expect(GazeFocusState.needsCalibration.label == "Needs calibration")
        #expect(GazeFocusState.needsPermission(.camera).label == "Needs Camera access")
        #expect(GazeFocusState.paused(.singleDisplay).label.contains("2 or more"))
    }
}
