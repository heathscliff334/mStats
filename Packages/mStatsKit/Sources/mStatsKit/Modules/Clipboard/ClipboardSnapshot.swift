import Foundation

public struct ClipboardEntry: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let text: String
    public let copiedAt: Date

    public init(id: UUID = UUID(), text: String, copiedAt: Date) {
        self.id = id
        self.text = text
        self.copiedAt = copiedAt
    }
}

public struct ClipboardSnapshot: Sendable {
    public let entries: [ClipboardEntry]

    public static let empty = ClipboardSnapshot(entries: [])

    public init(entries: [ClipboardEntry]) {
        self.entries = entries
    }
}
