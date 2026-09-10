import Foundation

/// SMC 4-char keys are undocumented and vary by Mac model/chip generation.
/// This is a best-effort, non-exhaustive list of keys seen across
/// community tools (smcFanControl, iStats gem, smckit); every read goes
/// through `SMCClient.readTemperature`/`readFanSpeed`, which return nil
/// (never a fake value) when a key isn't present on this Mac.
public enum SMCKeys {
    // CPU temperature — differs across Intel ("TC0P"/"TC0D") and Apple
    // Silicon generations ("Tp09", "Tp0T", etc. vary by chip).
    public static let cpuTemperatureCandidates = ["TC0P", "TC0D", "TC0E", "TC0F", "Tp09", "Tp0T", "Tp01"]
    public static let gpuTemperatureCandidates = ["TG0P", "TG0D", "Tg05", "Tg0D"]
    public static let batteryTemperatureCandidates = ["TB0T", "TB1T", "TB2T"]

    public static let fanCountKey = "FNum"
    public static func fanSpeedKey(index: Int) -> String { "F\(index)Ac" }
    public static func fanTargetKey(index: Int) -> String { "F\(index)Tg" }
}
