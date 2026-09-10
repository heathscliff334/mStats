import SwiftUI

public struct MemoryMenuBarLabel: View {
    @Bindable private var viewModel: MemoryViewModel

    public init(viewModel: MemoryViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let percent = viewModel.snapshot.map { $0.usedFraction * 100 }
        MenuBarPercentLabel(systemImage: "memorychip", percent: percent)
    }
}
