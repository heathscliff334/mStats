import SwiftUI

/// Fixed dark palette matching the reference design (near-black cards,
/// consistent per-metric series colors used across every module).
public enum Theme {
    public static let cardBackground = Color(red: 0.06, green: 0.06, blue: 0.09)
    public static let cardBorder = Color.white.opacity(0.06)
    public static let cardCornerRadius: CGFloat = 14

    public static let primaryText = Color.white
    public static let secondaryText = Color.white.opacity(0.55)
    public static let sectionLabel = Color.white.opacity(0.4)

    // Semantic series colors — kept identical everywhere the same kind of
    // value appears (e.g. "System" is always red, whether that's CPU system
    // time or memory wired).
    public static let seriesUser = Color(red: 0.30, green: 0.85, blue: 0.95)     // cyan
    public static let seriesSystem = Color(red: 0.95, green: 0.30, blue: 0.35)   // red
    public static let seriesCompressed = Color(red: 0.62, green: 0.42, blue: 0.95) // purple
    public static let seriesFree = Color.white.opacity(0.35)                     // gray
    public static let seriesCachedFiles = Color(red: 0.85, green: 0.70, blue: 0.35) // tan/gold
    public static let seriesRead = Color(red: 0.95, green: 0.30, blue: 0.35)     // red
    public static let seriesWrite = Color(red: 0.30, green: 0.85, blue: 0.95)    // cyan

    public static let ringTrack = Color.white.opacity(0.1)
    public static let warning = Color(red: 0.95, green: 0.75, blue: 0.25)
    public static let critical = Color(red: 0.95, green: 0.30, blue: 0.35)
    public static let success = Color(red: 0.35, green: 0.80, blue: 0.45)

    public static let cardWidth: CGFloat = 260
    public static let cardSpacing: CGFloat = 12
}
