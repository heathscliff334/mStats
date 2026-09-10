import SwiftUI

/// Shared placeholder for any metric a provider could not read (most
/// commonly Sensors, where SMC keys vary by Mac model/chip generation).
/// Never fake a value — show this instead.
public struct UnavailableStateView: View {
    private let reason: String

    public init(reason: String = "Unavailable on this Mac") {
        self.reason = reason
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "minus.circle")
                .foregroundStyle(Theme.secondaryText)
            Text(reason)
                .font(Typography.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }
}
