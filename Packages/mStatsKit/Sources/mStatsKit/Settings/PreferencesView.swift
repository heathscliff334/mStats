import SwiftUI

public struct PreferencesView: View {
    @Bindable private var settings: AppSettings

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var body: some View {
        Form {
            Section("Modules") {
                Toggle("CPU", isOn: $settings.cpuEnabled)
                Toggle("Memory", isOn: $settings.memoryEnabled)
                Toggle("Disk", isOn: $settings.diskEnabled)
                Toggle("Network", isOn: $settings.networkEnabled)
                Toggle("Sensors & Fans", isOn: $settings.sensorsEnabled)
                Toggle("Battery", isOn: $settings.batteryEnabled)
            }

            Section("Network") {
                Toggle("Show public IP address", isOn: $settings.publicIPEnabled)
                Text("Requires an outbound network request to a third-party IP-lookup service, on a low ~5 minute cadence separate from the live throughput graph.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Units") {
                Picker("Temperature", selection: $settings.temperatureUnit) {
                    Text("Celsius").tag(TemperatureUnit.celsius)
                    Text("Fahrenheit").tag(TemperatureUnit.fahrenheit)
                }
                Picker("Data rate", selection: $settings.byteRateUnit) {
                    Text("MB/s").tag(ByteRateUnit.bytesPerSecond)
                    Text("Mb/s").tag(ByteRateUnit.bitsPerSecond)
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLoginEnabled)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 420)
    }
}
