import SwiftUI

/// Shared "top processes" list reused by CPU, Memory and Disk cards, each
/// supplying its own value formatter (percent, bytes, bytes/sec).
public struct ProcessListView: View {
    private let title: String
    private let processes: [ProcessSnapshot]
    private let valueText: (ProcessSnapshot) -> String

    public init(title: String, processes: [ProcessSnapshot], valueText: @escaping (ProcessSnapshot) -> String) {
        self.title = title
        self.processes = processes
        self.valueText = valueText
    }

    public var body: some View {
        if !processes.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).sectionLabelStyle()
                ForEach(processes.prefix(5)) { process in
                    ProcessRow(process: process, valueText: valueText(process))
                }
            }
        }
    }
}
