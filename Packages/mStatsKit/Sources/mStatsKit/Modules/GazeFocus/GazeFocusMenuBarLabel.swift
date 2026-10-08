import SwiftUI

public struct GazeFocusMenuBarLabel: View {
    @Bindable private var viewModel: GazeFocusViewModel

    public init(viewModel: GazeFocusViewModel) {
        self.viewModel = viewModel
    }

    private var isActive: Bool {
        viewModel.snapshot.state == .active
    }

    public var body: some View {
        Image(systemName: isActive ? "eye" : "eye.slash")
            .foregroundStyle(.white.opacity(isActive ? 1 : 0.5))
    }
}
