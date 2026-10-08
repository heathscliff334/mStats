import SwiftUI

public struct PreferencesView: View {
    @Bindable private var settings: AppSettings
    private let gazeFocus: GazeFocusViewModel?

    public init(settings: AppSettings, gazeFocus: GazeFocusViewModel? = nil) {
        self.settings = settings
        self.gazeFocus = gazeFocus
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

            if let gazeFocus {
                GazeFocusPreferencesSection(settings: settings, viewModel: gazeFocus)
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
        .frame(width: 420, height: 640)
    }
}

private struct GazeFocusPreferencesSection: View {
    @Bindable var settings: AppSettings
    @Bindable var viewModel: GazeFocusViewModel

    var body: some View {
        Section("Gaze Focus") {
            Toggle("Move focus to the display I'm looking at", isOn: $settings.gazeFocusEnabled)
            Text("Off by default. Uses the camera to tell which display you're looking at, then moves keyboard focus there after a short glance. Camera frames are processed in memory and never stored or sent.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LabeledContent("Status", value: viewModel.snapshot.state.label)

            if let issue = viewModel.permissionIssue {
                HStack {
                    Text("\(issue.title) access is needed. Allow mStats in System Settings, then turn this on again.")
                        .font(.caption)
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Open Settings") { NSWorkspace.shared.open(issue.settingsURL) }
                }
            }

            if let summary = viewModel.calibrationSummary {
                LabeledContent("Calibration", value: summary.quality)
            } else {
                LabeledContent("Calibration", value: "Not calibrated")
            }
            if let message = viewModel.calibrationMessage {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button(viewModel.calibrationSummary == nil ? "Calibrate…" : "Recalibrate…") {
                    viewModel.requestCalibration()
                }
                if viewModel.calibrationSummary != nil {
                    Button("Reset") { viewModel.resetCalibration() }
                }
            }

            LabeledContent("Glance time") {
                Slider(value: $settings.gazeFocusDwellMs, in: 150...800, step: 50)
                    .frame(width: 140)
                Text("\(Int(settings.gazeFocusDwellMs)) ms").monospacedDigit().frame(width: 60, alignment: .trailing)
            }
            LabeledContent("Typing guard") {
                Slider(value: $settings.gazeFocusTypingGuardMs, in: 300...3000, step: 100)
                    .frame(width: 140)
                Text(String(format: "%.1f s", settings.gazeFocusTypingGuardMs / 1000))
                    .monospacedDigit().frame(width: 60, alignment: .trailing)
            }
            LabeledContent("Confidence") {
                Slider(value: $settings.gazeFocusMinConfidence, in: 0.05...0.6, step: 0.05)
                    .frame(width: 140)
                Text(String(format: "%.2f", settings.gazeFocusMinConfidence))
                    .monospacedDigit().frame(width: 60, alignment: .trailing)
            }
            Text("Glance time is how long you must look before it switches. The typing guard stops it switching while you type. Raise confidence if it switches by mistake; lower it if it misses glances.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Also move the pointer", isOn: $settings.gazeFocusMovePointer)
            Toggle("Pause in Low Power Mode", isOn: $settings.gazeFocusPauseOnLowPower)
        }
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
