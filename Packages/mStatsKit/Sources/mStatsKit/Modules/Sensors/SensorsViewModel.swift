import Foundation

public typealias SensorsViewModel = ModuleViewModel<SensorsProvider>

public extension ModuleViewModel where Provider == SensorsProvider {
    convenience init(settings: AppSettings) {
        self.init(
            provider: SensorsProvider(),
            category: "Sensors",
            pollInterval: { [weak settings] in settings?.sensorsPollInterval ?? 3.0 }
        )
    }
}
