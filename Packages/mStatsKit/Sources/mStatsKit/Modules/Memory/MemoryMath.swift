import Foundation

/// Pure heuristic extracted from MemoryProvider so it's testable with
/// fixture page counts, with no live `host_statistics64` syscall involved.
///
/// macOS's raw page buckets (free/active/inactive/wired/compressor) always
/// sum to ~100% of physical RAM by construction, because macOS aggressively
/// fills "free" RAM with a reclaimable file-backed cache (Activity Monitor's
/// "Cached Files") rather than leaving it idle. That cache is not "used"
/// memory in any meaningful sense — it's evicted on demand. Naively reporting
/// (total - free) / total as "memory used" therefore reads ~100% almost all
/// the time, which is misleading (this is exactly the bug that produced a
/// 99-100% ring on this app while Activity Monitor read ~87%).
///
/// This mirrors Activity Monitor's own categorization: split pages into
/// App (real, non-reclaimable process memory), Wired, Compressed, reclaimable
/// Cached Files, and Free — and treat only App+Wired+Compressed as "used".
enum MemoryMath {
    struct Breakdown: Equatable {
        let free: UInt64
        let wired: UInt64
        let compressed: UInt64
        let cachedFiles: UInt64
        let app: UInt64
    }

    static func breakdown(
        pageSize: UInt64,
        freeCount: UInt64,
        speculativeCount: UInt64,
        wireCount: UInt64,
        compressorPageCount: UInt64,
        externalPageCount: UInt64,
        internalPageCount: UInt64,
        purgeableCount: UInt64
    ) -> Breakdown {
        let free = (freeCount &+ speculativeCount) &* pageSize
        let wired = wireCount &* pageSize
        let compressed = compressorPageCount &* pageSize
        // external/internal page counts include purgeable pages that are
        // reclaimable like cache but not attributed to a live app; excluding
        // them from both buckets avoids double counting and matches how
        // Activity Monitor's ledger nets out.
        let cachedFiles = externalPageCount > purgeableCount
            ? (externalPageCount - purgeableCount) &* pageSize : 0
        let app = internalPageCount > purgeableCount
            ? (internalPageCount - purgeableCount) &* pageSize : 0
        return Breakdown(free: free, wired: wired, compressed: compressed, cachedFiles: cachedFiles, app: app)
    }

    /// Fraction shown as the "memory used" ring — explicitly excludes both
    /// Free and reclaimable Cached Files, so it tracks Activity Monitor's
    /// "Memory Used" instead of pinning near 100%.
    static func usedFraction(total: UInt64, wired: UInt64, compressed: UInt64, app: UInt64) -> Double {
        guard total > 0 else { return 0 }
        let used = wired &+ compressed &+ app
        return min(1.0, Double(used) / Double(total))
    }
}
