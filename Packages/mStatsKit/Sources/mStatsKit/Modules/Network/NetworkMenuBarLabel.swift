import SwiftUI

public struct NetworkMenuBarLabel: View {
    @Bindable private var viewModel: NetworkViewModel

    public init(viewModel: NetworkViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        MenuBarSparklineLabel(systemImage: "network", values: viewModel.downloadHistory.values)
    }
}
