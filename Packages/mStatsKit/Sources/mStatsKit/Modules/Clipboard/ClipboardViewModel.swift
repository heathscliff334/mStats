import Foundation
import Observation
#if canImport(AppKit)
import AppKit
#endif

/// Session-only clipboard history. Doesn't fit the `SystemMetricProvider`
/// pattern (there's no async syscall to poll — `NSPasteboard` is simple
/// synchronous state), so this talks to `NSPasteboard.general` directly.
/// History lives only in this in-memory array — never written to
/// UserDefaults/disk, and it's gone the moment the app quits, matching the
/// "session-only" requirement.
@Observable
@MainActor
public final class ClipboardViewModel {
    public static let maxHistoryItems = 30

    public private(set) var snapshot: ClipboardSnapshot = .empty

    private let settings: AppSettings
    private let logger = MetricLog.logger("Clipboard")
    private nonisolated(unsafe) var pollTask: Task<Void, Never>?

    #if canImport(AppKit)
    private let pasteboard = NSPasteboard.general
    #endif
    private var lastSeenChangeCount = -1

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public func startPolling() {
        guard pollTask == nil else { return }
        #if canImport(AppKit)
        lastSeenChangeCount = pasteboard.changeCount
        #endif
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.checkForChange()
                try? await Task.sleep(for: .seconds(0.75))
            }
        }
    }

    public func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func checkForChange() {
        #if canImport(AppKit)
        guard pasteboard.changeCount != lastSeenChangeCount else { return }
        lastSeenChangeCount = pasteboard.changeCount

        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard !ClipboardPrivacy.shouldSkip(types: types) else { return }

        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard snapshot.entries.first?.text != text else { return }

        var entries = snapshot.entries
        entries.insert(ClipboardEntry(text: text, copiedAt: Date()), at: 0)
        if entries.count > Self.maxHistoryItems {
            entries.removeLast(entries.count - Self.maxHistoryItems)
        }
        snapshot = ClipboardSnapshot(entries: entries)

        if MetricLog.debugStdout {
            print("[Clipboard] recorded entry (\(entries.count) total)")
        }
        logger.debug("recorded entry (\(entries.count, privacy: .public) total)")
        #endif
    }

    /// Copies `entry` back to the pasteboard so the user can paste it, while
    /// advancing `lastSeenChangeCount` past our own write so the next poll
    /// doesn't re-record the exact same text as a "new" entry.
    public func copyBack(_ entry: ClipboardEntry) {
        #if canImport(AppKit)
        pasteboard.clearContents()
        pasteboard.setString(entry.text, forType: .string)
        lastSeenChangeCount = pasteboard.changeCount
        #endif
    }

    public func clearHistory() {
        snapshot = .empty
    }

    deinit {
        pollTask?.cancel()
    }
}
