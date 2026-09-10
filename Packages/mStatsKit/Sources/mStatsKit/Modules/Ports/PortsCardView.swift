import SwiftUI

/// Pure so it can be unit tested without constructing any SwiftUI/view state.
public enum PortsFilter {
    public static func matches(_ entry: PortEntry, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if entry.processName.localizedCaseInsensitiveContains(trimmed) { return true }
        return String(entry.port).contains(trimmed)
    }
}

public struct PortsCardView: View {
    @Bindable private var viewModel: PortsViewModel
    @State private var pendingAction: PendingAction?
    @State private var searchQuery: String = ""

    private struct PendingAction: Identifiable {
        let entry: PortEntry
        let isForceKill: Bool
        var id: String { entry.id + (isForceKill ? "-force" : "-stop") }
    }

    public init(viewModel: PortsViewModel) {
        self.viewModel = viewModel
    }

    private var filteredEntries: [PortEntry] {
        viewModel.snapshot.entries.filter { PortsFilter.matches($0, query: searchQuery) }
    }

    public var body: some View {
        CardView(title: "Listening Ports") {
            if let error = viewModel.lastActionError {
                Text(error)
                    .font(Typography.caption)
                    .foregroundStyle(Theme.critical)
            }

            if !viewModel.snapshot.entries.isEmpty {
                searchField
            }

            if viewModel.snapshot.entries.isEmpty {
                UnavailableStateView(reason: "No listening ports found")
            } else {
                let entries = filteredEntries
                if entries.isEmpty {
                    UnavailableStateView(reason: "No matching ports")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(entries) { entry in
                                row(for: entry)
                                if entry.id != entries.last?.id {
                                    Divider().overlay(Theme.cardBorder)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }
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
            Button(action.isForceKill ? "Force Kill" : "Stop", role: .destructive) {
                let action = action
                Task {
                    if action.isForceKill {
                        await viewModel.forceKill(entry: action.entry)
                    } else {
                        await viewModel.stop(entry: action.entry)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text("\(action.isForceKill ? "Force kill" : "Stop") \(action.entry.processName) (PID \(String(action.entry.pid))), listening on \(action.entry.protocolKind.rawValue) port \(String(action.entry.port))?")
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryText)
                .font(.system(size: 12))
            TextField("Search name or port", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(Typography.caption)
                .foregroundStyle(Theme.primaryText)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.secondaryText)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.cardBorder.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.bottom, 4)
    }

    private func row(for entry: PortEntry) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.processName)
                        .font(Typography.legendValue)
                        .foregroundStyle(Theme.primaryText)
                    if entry.isDevPort {
                        Text("DEV")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Theme.seriesUser.opacity(0.25))
                            .foregroundStyle(Theme.seriesUser)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }
                Text("\(entry.protocolKind.rawValue) · \(entry.address):\(String(entry.port)) · PID \(String(entry.pid))")
                    .font(Typography.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            Menu {
                Button("Stop") { pendingAction = PendingAction(entry: entry, isForceKill: false) }
                Button("Force Kill", role: .destructive) { pendingAction = PendingAction(entry: entry, isForceKill: true) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(Theme.secondaryText)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
        }
    }
}
