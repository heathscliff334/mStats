import SwiftUI

/// The dark rounded container every module's dropdown content sits in.
public struct CardView<Content: View>: View {
    private let title: String?
    private let content: Content

    public init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title).sectionLabelStyle()
            }
            content
        }
        .padding(16)
        .frame(width: Theme.cardWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .fill(Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous)
                .stroke(Theme.cardBorder, lineWidth: 1)
        )
    }
}
