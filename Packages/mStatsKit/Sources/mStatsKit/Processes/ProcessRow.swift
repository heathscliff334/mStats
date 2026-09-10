import SwiftUI

public struct ProcessRow: View {
    private let process: ProcessSnapshot
    private let valueText: String

    public init(process: ProcessSnapshot, valueText: String) {
        self.process = process
        self.valueText = valueText
    }

    public var body: some View {
        LegendRow(label: process.name, value: valueText)
    }
}
