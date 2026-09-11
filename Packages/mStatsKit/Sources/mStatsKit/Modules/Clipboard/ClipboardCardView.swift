import SwiftUI

public struct ClipboardCardView: View {
    @Bindable private var viewModel: ClipboardViewModel

    public init(viewModel: ClipboardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        CardView(title: "Clipboard History") {
            if viewModel.snapshot.entries.isEmpty {
                UnavailableStateView(reason: "Nothing copied yet")
            } else {
                HStack {
                    Text("\(viewModel.snapshot.entries.count) item\(viewModel.snapshot.entries.count == 1 ? "" : "s")")
                        .font(Typography.caption)
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Button("Clear") {
                        viewModel.clearHistory()
                    }
                    .buttonStyle(.plain)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.critical)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.snapshot.entries) { entry in
                            row(for: entry)
                            if entry.id != viewModel.snapshot.entries.last?.id {
                                Divider().overlay(Theme.cardBorder)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
    }

    private func row(for entry: ClipboardEntry) -> some View {
        Button {
            viewModel.copyBack(entry)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.text)
                    .font(Typography.legendValue)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(Formatting.relativeTime(entry.copiedAt))
                    .font(Typography.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to copy back")
    }
}
