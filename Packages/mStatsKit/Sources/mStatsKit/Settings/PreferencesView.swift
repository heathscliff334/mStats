import SwiftUI

public struct PreferencesView: View {
    @Bindable private var settings: AppSettings

    public init(settings: AppSettings) {
        self.settings = settings
    }

    public var body: some View {
        Form {
            Section("Menu Bar") {
                Toggle("Combine all icons into one overview icon", isOn: $settings.combinedIconEnabled)
                Text("Shows a single menu bar icon with tabs to switch between enabled modules, instead of one icon per module.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Modules") {
                Toggle("CPU", isOn: $settings.cpuEnabled)
                Toggle("Memory", isOn: $settings.memoryEnabled)
                Toggle("Disk", isOn: $settings.diskEnabled)
                Toggle("Network", isOn: $settings.networkEnabled)
                Toggle("Sensors & Fans", isOn: $settings.sensorsEnabled)
                Toggle("Battery", isOn: $settings.batteryEnabled)
                Toggle("Ports", isOn: $settings.portsEnabled)
                Toggle("Docker", isOn: $settings.dockerEnabled)
                Text("Its menu bar icon only appears when Docker Desktop is actually running — this toggle just opts in/out of that auto-detection.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Clipboard History", isOn: $settings.clipboardEnabled)
                Text("Session-only — history clears when mStats quits and is never written to disk. Skips anything password managers mark as sensitive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            Section("Keyboard Shortcuts") {
                ShortcutRow(action: "Open Clipboard History", keys: "⌘⇧V")
                Text("Works from any app — no need to click the menu bar icon first. Requires Clipboard History to be enabled above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 500)
    }
}

private struct ShortcutRow: View {
    let action: String
    let keys: String

    var body: some View {
        HStack {
            Text(action)
            Spacer()
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
