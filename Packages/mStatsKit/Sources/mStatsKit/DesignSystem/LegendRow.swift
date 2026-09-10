import SwiftUI

/// Colored dot + label + right-aligned monospaced value, used throughout
/// every card for a consistent alignment grid.
public struct LegendRow: View {
    private let color: Color?
    private let label: String
    private let value: String

    public init(color: Color? = nil, label: String, value: String) {
        self.color = color
        self.label = label
        self.value = value
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let color {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
            Text(label)
                .font(Typography.legendLabel)
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .font(Typography.legendValue)
                .foregroundStyle(Theme.primaryText)
        }
    }
}
