import Foundation

public typealias BatteryViewModel = ModuleViewModel<BatteryProvider>

public extension ModuleViewModel where Provider == BatteryProvider {
    convenience init(settings: AppSettings) {
        self.init(
            provider: BatteryProvider(),
            category: "Battery",
            pollInterval: { [weak settings] in settings?.batteryPollInterval ?? 5.0 }
        )
    }
}
