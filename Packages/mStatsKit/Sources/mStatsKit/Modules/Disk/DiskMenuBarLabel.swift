import SwiftUI

public struct DiskMenuBarLabel: View {
    @Bindable private var viewModel: DiskViewModel

    public init(viewModel: DiskViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        MenuBarSparklinePercentLabel(
            systemImage: "internaldrive",
            values: viewModel.readHistory.values,
            percent: viewModel.snapshot.primaryVolumeUsedPercent
        )
    }
}
