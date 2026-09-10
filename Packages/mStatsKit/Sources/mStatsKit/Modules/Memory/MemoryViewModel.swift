import Foundation

public typealias MemoryViewModel = ModuleViewModel<MemoryProvider>

public extension ModuleViewModel where Provider == MemoryProvider {
    convenience init(settings: AppSettings) {
        self.init(
            provider: MemoryProvider(),
            category: "Memory",
            pollInterval: { [weak settings] in settings?.memoryPollInterval ?? 2.0 }
        )
    }
}
