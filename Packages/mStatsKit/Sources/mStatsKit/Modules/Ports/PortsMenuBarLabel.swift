import SwiftUI

public struct PortsMenuBarLabel: View {
    @Bindable private var viewModel: PortsViewModel

    public init(viewModel: PortsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let devCount = viewModel.snapshot.entries.filter(\.isDevPort).count
        MenuBarTextLabel(systemImage: "point.3.connected.trianglepath.dotted", text: "\(devCount)")
    }
}
