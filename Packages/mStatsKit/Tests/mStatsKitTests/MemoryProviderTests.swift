import Testing
@testable import mStatsKit

@Suite struct MemoryProviderTests {
    // Fixture modeled on the user's own side-by-side Activity Monitor reading:
    // 16GB physical, ~87% used (App 4.36GB / Wired 2.48GB / Compressed 6.49GB),
    // ~1.99GB reclaimable Cached Files, rest free. Page size 16384 (Apple Silicon).
    private static let pageSize: UInt64 = 16384
    private static let total: UInt64 = 16_000_000_000

    private static func pages(_ bytes: UInt64) -> UInt64 { bytes / pageSize }

    @Test func breakdownExcludesCachedFilesAndFreeFromUsedBuckets() {
        let internalPages = Self.pages(4_360_000_000)
        let externalPages = Self.pages(1_990_000_000)
        let purgeablePages: UInt64 = 0

        let breakdown = MemoryMath.breakdown(
            pageSize: Self.pageSize,
            freeCount: Self.pages(1_170_000_000),
            speculativeCount: 0,
            wireCount: Self.pages(2_480_000_000),
            compressorPageCount: Self.pages(6_490_000_000),
            externalPageCount: externalPages,
            internalPageCount: internalPages,
            purgeableCount: purgeablePages
        )

        #expect(breakdown.app == internalPages * Self.pageSize)
        #expect(breakdown.cachedFiles == externalPages * Self.pageSize)
        #expect(breakdown.wired == Self.pages(2_480_000_000) * Self.pageSize)
        #expect(breakdown.compressed == Self.pages(6_490_000_000) * Self.pageSize)
    }

    @Test func usedFractionMatchesActivityMonitorNotRawFreeComplement() {
        // App + Wired + Compressed ≈ 4.36 + 2.48 + 6.49 = 13.33GB of 16GB ≈ 83-87%,
        // NOT ~100% (which the old (total-free)/total heuristic produced, since
        // "free" is nearly always tiny — the bug this test guards against).
        let fraction = MemoryMath.usedFraction(
            total: Self.total,
            wired: 2_480_000_000,
            compressed: 6_490_000_000,
            app: 4_360_000_000
        )
        #expect(fraction > 0.75)
        #expect(fraction < 0.92)
    }

    @Test func usedFractionIsNotPinnedNearOneHundredPercentWhenCacheIsLarge() {
        // Even if external/cache pages are huge (macOS filling spare RAM),
        // the fraction should stay driven by real usage, not by (total-free).
        let fraction = MemoryMath.usedFraction(
            total: Self.total,
            wired: 1_000_000_000,
            compressed: 500_000_000,
            app: 2_000_000_000
        )
        #expect(fraction < 0.5)
    }

    @Test func breakdownClampsToZeroWhenPurgeableExceedsInternalOrExternal() {
        let breakdown = MemoryMath.breakdown(
            pageSize: 16384,
            freeCount: 100,
            speculativeCount: 0,
            wireCount: 100,
            compressorPageCount: 100,
            externalPageCount: 50,
            internalPageCount: 50,
            purgeableCount: 1_000 // exceeds both — must clamp, not underflow
        )
        #expect(breakdown.app == 0)
        #expect(breakdown.cachedFiles == 0)
    }

    @Test func usedFractionClampsToOneWhenBucketsExceedTotal() {
        // Guards against an inconsistent snapshot producing >100%.
        let fraction = MemoryMath.usedFraction(total: 100, wired: 60, compressed: 60, app: 60)
        #expect(fraction == 1.0)
    }
}
