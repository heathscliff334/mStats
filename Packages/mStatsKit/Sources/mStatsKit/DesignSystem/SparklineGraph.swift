import SwiftUI

public struct SparklineSeries: Sendable {
    public let values: [Double]
    public let color: Color

    public init(values: [Double], color: Color) {
        self.values = values
        self.color = color
    }
}

/// Canvas-based time-series graph (deliberately not Swift Charts, so redraws
/// are driven purely by new poll samples rather than an animation-driven
/// layout pass — keeps idle CPU near zero between polls).
public struct SparklineGraph: View {
    private let series: [SparklineSeries]
    private let maxValue: Double?
    private let style: Style

    public enum Style {
        case line
        case bar
    }

    public init(series: [SparklineSeries], maxValue: Double? = nil, style: Style = .line) {
        self.series = series
        self.maxValue = maxValue
        self.style = style
    }

    public var body: some View {
        Canvas { context, size in
            let peak = maxValue ?? series.flatMap(\.values).max().flatMap { $0 > 0 ? $0 : nil } ?? 1

            for s in series {
                guard !s.values.isEmpty else { continue }
                let stepX = s.values.count > 1 ? size.width / CGFloat(s.values.count - 1) : size.width

                switch style {
                case .line:
                    var path = Path()
                    for (index, value) in s.values.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = size.height - (CGFloat(value / peak) * size.height)
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    context.stroke(path, with: .color(s.color), lineWidth: 1.5)

                case .bar:
                    let barWidth = max(1, size.width / CGFloat(s.values.count) - 1)
                    for (index, value) in s.values.enumerated() {
                        let x = CGFloat(index) * stepX
                        let height = CGFloat(value / peak) * size.height
                        let rect = CGRect(x: x, y: size.height - height, width: barWidth, height: height)
                        context.fill(Path(rect), with: .color(s.color))
                    }
                }
            }
        }
        .frame(height: 60)
    }
}
