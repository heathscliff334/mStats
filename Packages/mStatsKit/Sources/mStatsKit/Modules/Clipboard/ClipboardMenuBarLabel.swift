import SwiftUI

public struct ClipboardMenuBarLabel: View {
    @Bindable private var viewModel: ClipboardViewModel

    public init(viewModel: ClipboardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        MenuBarIconOnlyLabel(systemImage: "doc.on.clipboard")
    }
}
