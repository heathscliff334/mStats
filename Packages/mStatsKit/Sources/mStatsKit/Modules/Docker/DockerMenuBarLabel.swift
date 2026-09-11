import SwiftUI

public struct DockerMenuBarLabel: View {
    @Bindable private var viewModel: DockerViewModel

    public init(viewModel: DockerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let runningCount = viewModel.snapshot.containers.filter(\.isRunning).count
        MenuBarTextLabel(systemImage: "shippingbox", text: "\(runningCount)")
    }
}
