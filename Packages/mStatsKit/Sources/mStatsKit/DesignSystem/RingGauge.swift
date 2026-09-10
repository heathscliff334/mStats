import SwiftUI

/// Single-value ring gauge (e.g. "94% / 19:46" in the reference), with an
/// optional two-line center label.
public struct RingGauge: View {
    private let progress: Double // 0...1
    private let color: Color
    private let lineWidth: CGFloat
    private let primaryLabel: String
    private let secondaryLabel: String?

    public init(
        progress: Double,
        color: Color,
        lineWidth: CGFloat = 6,
        primaryLabel: String,
        secondaryLabel: String? = nil
    ) {
        self.progress = min(max(progress, 0), 1)
        self.color = color
        self.lineWidth = lineWidth
        self.primaryLabel = primaryLabel
        self.secondaryLabel = secondaryLabel
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.ringTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: progress)
            VStack(spacing: 2) {
                Text(primaryLabel)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primaryText)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                if let secondaryLabel {
                    Text(secondaryLabel)
                        .font(Typography.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            .padding(6)
        }
        .frame(width: 78, height: 78)
    }
}
