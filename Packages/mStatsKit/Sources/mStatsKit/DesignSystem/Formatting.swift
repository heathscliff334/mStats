import Foundation

public enum Formatting {
    public static func bytes(_ value: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: Int64(value))
    }

    /// e.g. "2m ago" — used by Clipboard history rows. Builds a fresh
    /// formatter per call rather than caching one, since
    /// `RelativeDateTimeFormatter` isn't `Sendable` and this needs to be
    /// safely callable under Swift 6 strict concurrency.
    public static func relativeTime(_ date: Date, since now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
