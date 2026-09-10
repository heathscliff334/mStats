import SwiftUI

public enum Typography {
    public static func headline(_ size: CGFloat = 30) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    public static let sectionLabel: Font = .system(size: 11, weight: .semibold, design: .default)
        .smallCaps()

    public static let legendLabel: Font = .system(size: 12, weight: .medium)
    public static let legendValue: Font = .system(size: 12, weight: .semibold).monospacedDigit()
    public static let caption: Font = .system(size: 11, weight: .regular)
}

public extension View {
    /// Applies the uppercase-tracked section header look used at the top of
    /// every card (e.g. "PROCESSES", "TEMPERATURE").
    func sectionLabelStyle() -> some View {
        self
            .font(Typography.sectionLabel)
            .foregroundStyle(Theme.sectionLabel)
            .textCase(.uppercase)
    }
}
