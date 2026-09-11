import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Small trailing icon button that copies `value` to the pasteboard and
/// briefly shows a checkmark for feedback. Reusable anywhere a raw
/// identifier (IP address, path, key, …) is shown and worth copying.
public struct CopyIconButton: View {
    private let value: String
    @State private var didCopy = false

    public init(value: String) {
        self.value = value
    }

    public var body: some View {
        Button {
            copy()
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .foregroundStyle(didCopy ? Theme.seriesUser : Theme.secondaryText)
                .font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .frame(width: 16)
        .help("Copy to clipboard")
    }

    private func copy() {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            didCopy = false
        }
    }
}

/// A value row (e.g. an IP address) with a trailing copy button.
public struct CopyableValueRow: View {
    private let value: String

    public init(value: String) {
        self.value = value
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(value)
                .font(Typography.legendValue)
                .foregroundStyle(Theme.primaryText)
            Spacer(minLength: 8)
            CopyIconButton(value: value)
        }
    }
}
