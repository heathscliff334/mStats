import SwiftUI

public struct CPUMenuBarLabel: View {
    @Bindable private var viewModel: CPUViewModel

    public init(viewModel: CPUViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        MenuBarPercentLabel(
            systemImage: "cpu",
            percent: viewModel.snapshot.userPercent + viewModel.snapshot.systemPercent
        )
    }
}
