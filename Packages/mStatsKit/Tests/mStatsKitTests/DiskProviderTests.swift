import Testing
@testable import mStatsKit

@Suite struct DiskProviderTests {
    @Test func halfUsedVolumeReportsFiftyPercent() {
        let percent = DiskMath.usedPercent(totalBytes: 1_000, availableBytes: 500)
        #expect(percent == 50)
    }

    @Test func fullVolumeReportsHundredPercent() {
        let percent = DiskMath.usedPercent(totalBytes: 1_000, availableBytes: 0)
        #expect(percent == 100)
    }

    @Test func zeroTotalReportsNil() {
        let percent = DiskMath.usedPercent(totalBytes: 0, availableBytes: 0)
        #expect(percent == nil)
    }

    @Test func availableExceedingTotalClampsToZeroUsed() {
        // Defensive: volumeAvailableCapacityForImportantUsage can slightly
        // exceed the reported total on some filesystems.
        let percent = DiskMath.usedPercent(totalBytes: 1_000, availableBytes: 1_200)
        #expect(percent == 0)
    }
}
