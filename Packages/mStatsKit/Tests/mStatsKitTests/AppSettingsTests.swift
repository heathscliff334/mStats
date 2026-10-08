import Testing
import Foundation
@testable import mStatsKit

@MainActor
@Suite struct AppSettingsTests {
    private func freshDefaults() -> UserDefaults {
        let suiteName = "com.hartono.mStatsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func defaultsMatchDocumentedValues() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.cpuEnabled == true)
        #expect(settings.memoryEnabled == true)
        #expect(settings.diskEnabled == true)
        #expect(settings.networkEnabled == true)
        #expect(settings.sensorsEnabled == true)
        #expect(settings.batteryEnabled == true)
        #expect(settings.portsEnabled == true)
        #expect(settings.dockerEnabled == true)
        #expect(settings.clipboardEnabled == false)
        #expect(settings.publicIPEnabled == false)
        #expect(settings.launchAtLoginEnabled == false)
        #expect(settings.cpuPollInterval == 1.0)
        #expect(settings.networkPollInterval == 1.0)
        #expect(settings.memoryPollInterval == 2.0)
        #expect(settings.diskPollInterval == 3.0)
        #expect(settings.sensorsPollInterval == 3.0)
        #expect(settings.batteryPollInterval == 5.0)
        #expect(settings.portsPollInterval == 4.0)
        #expect(settings.dockerPollInterval == 5.0)
        #expect(settings.publicIPPollInterval == 300.0)
        #expect(settings.temperatureUnit == .celsius)
        #expect(settings.byteRateUnit == .bytesPerSecond)
    }

    @Test func gazeFocusIsOffByDefaultWithDocumentedValues() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.gazeFocusEnabled == false)
        #expect(settings.gazeFocusDwellMs == 300)
        #expect(settings.gazeFocusTypingGuardMs == 1000)
        #expect(settings.gazeFocusMovePointer == false)
        #expect(settings.gazeFocusPauseOnLowPower == true)
        #expect(settings.gazeFocusMinConfidence == 0.2)
        #expect(settings.gazeFocusCalibrationData == nil)
    }

    @Test func gazeFocusSettingsPersistAcrossInstances() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.gazeFocusEnabled = true
        first.gazeFocusDwellMs = 450
        first.gazeFocusMovePointer = true
        first.gazeFocusCalibrationData = Data([1, 2, 3])

        let second = AppSettings(defaults: defaults)
        #expect(second.gazeFocusEnabled == true)
        #expect(second.gazeFocusDwellMs == 450)
        #expect(second.gazeFocusMovePointer == true)
        #expect(second.gazeFocusCalibrationData == Data([1, 2, 3]))

        second.gazeFocusCalibrationData = nil
        #expect(AppSettings(defaults: defaults).gazeFocusCalibrationData == nil)
    }

    @Test func outOfRangeGazeFocusValuesAreClamped() {
        let defaults = freshDefaults()
        defaults.set(99_999.0, forKey: "gazeFocusDwellMs")
        defaults.set(0.0, forKey: "gazeFocusTypingGuardMs")
        defaults.set(5.0, forKey: "gazeFocusMinConfidence")
        let settings = AppSettings(defaults: defaults)
        #expect(settings.gazeFocusDwellMs == 1500)
        #expect(settings.gazeFocusTypingGuardMs == 200)
        #expect(settings.gazeFocusMinConfidence == 0.8)
    }

    @Test func togglingAModulePersistsAcrossInstances() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.cpuEnabled = false
        first.cpuPollInterval = 2.5

        let second = AppSettings(defaults: defaults)
        #expect(second.cpuEnabled == false)
        #expect(second.cpuPollInterval == 2.5)
        // Untouched modules stay at their documented defaults.
        #expect(second.memoryEnabled == true)
    }

    @Test func publicIPEnabledPersists() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.publicIPEnabled = true

        let second = AppSettings(defaults: defaults)
        #expect(second.publicIPEnabled == true)
    }

    @Test func temperatureFormatting() {
        #expect(TemperatureUnit.celsius.format(20) == "20°C")
        #expect(TemperatureUnit.fahrenheit.format(0) == "32°F")
    }

    @Test func byteRateFormattingUsesBinaryUnits() {
        let formatted = ByteRateUnit.bytesPerSecond.format(1_048_576) // 1 MiB/s
        #expect(formatted == "1.0 MB/s")
    }
}
