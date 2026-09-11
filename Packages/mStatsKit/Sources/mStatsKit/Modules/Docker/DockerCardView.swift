import SwiftUI

public struct DockerCardView: View {
    @Bindable private var viewModel: DockerViewModel
    @State private var pendingAction: PendingAction?

    private enum Kind { case stop, restart }

    private struct PendingAction: Identifiable {
        let container: ContainerEntry
        let kind: Kind
        var id: String { container.id + "-\(kind)" }
    }

    public init(viewModel: DockerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        CardView(title: "Docker") {
            if let error = viewModel.lastActionError {
                Text(error)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.critical)
            }

            if viewModel.snapshot.containers.isEmpty {
                UnavailableStateView(reason: "No containers")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.snapshot.containers) { container in
                            row(for: container)
                            if container.id != viewModel.snapshot.containers.last?.id {
                                Divider().overlay(Theme.cardBorder)
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
        }
        .confirmationDialog(
            "Confirm Action",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { isPresented in if !isPresented { pendingAction = nil } }
            ),
            presenting: pendingAction
        ) { action in
            Button(action.kind == .stop ? "Stop" : "Restart", role: .destructive) {
                let action = action
                Task {
                    if action.kind == .stop {
                        await viewModel.stop(container: action.container)
                    } else {
                        await viewModel.restart(container: action.container)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text("\(action.kind == .stop ? "Stop" : "Restart") container \(action.container.name)?")
        }
    }

    private func row(for container: ContainerEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(container.name)
                    .font(Typography.legendValue)
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text(container.image)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                Text(statsLine(for: container))
                    .font(Typography.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                if container.isRunning {
                    actionIconButton(systemImage: "stop.fill", tint: Theme.warning, help: "Stop") {
                        pendingAction = PendingAction(container: container, kind: .stop)
                    }
                    actionIconButton(systemImage: "arrow.clockwise", tint: Theme.warning, help: "Restart") {
                        pendingAction = PendingAction(container: container, kind: .restart)
                    }
                } else {
                    actionIconButton(systemImage: "play.fill", tint: Theme.success, help: "Start") {
                        Task { await viewModel.start(container: container) }
                    }
                }
            }
        }
    }

    private func statsLine(for container: ContainerEntry) -> String {
        if container.isRunning, let cpu = container.cpuPercentText, let mem = container.memoryUsageText {
            return "\(cpu) CPU · \(mem)"
        }
        return container.status
    }

    private func actionIconButton(systemImage: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
