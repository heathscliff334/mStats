import Foundation
import IOKit
import CSystemShims

/// SMC (System Management Controller) access via IOKit's "AppleSMC" user
/// client. There is no public Apple header for this — the struct layout and
/// selectors here match the long-standing community reverse-engineering
/// (smcFanControl, osx-cpu-temp, iStats gem, smckit) used successfully for
/// over a decade. The IOKit connection is serialized through this actor
/// since `io_connect_t` isn't safe to call concurrently.
public actor SMCClient {
    public static let shared = SMCClient()

    // nonisolated(unsafe): only touched from within this actor's own
    // isolated methods, except in deinit (always nonisolated) where it's
    // safe because no other access can be in flight once deinit runs.
    private nonisolated(unsafe) var connection: io_connect_t = 0
    private nonisolated(unsafe) var isOpen = false

    private init() {}

    public func readTemperature(candidateKeys: [String]) -> Double? {
        for key in candidateKeys {
            if let value = readValue(key: key), value > 0, value < 200 {
                return value
            }
        }
        return nil
    }

    public func fanCount() -> Int? {
        guard let value = readValue(key: SMCKeys.fanCountKey) else { return nil }
        return Int(value)
    }

    public func fanSpeed(index: Int) -> (current: Double, target: Double)? {
        guard let current = readValue(key: SMCKeys.fanSpeedKey(index: index)) else { return nil }
        let target = readValue(key: SMCKeys.fanTargetKey(index: index))
        return (current, target ?? current)
    }

    private func open() -> Bool {
        if isOpen { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        isOpen = (result == kIOReturnSuccess)
        return isOpen
    }

    private func readValue(key: String) -> Double? {
        guard open(), let keyCode = Self.fourCharCode(key) else { return nil }

        var infoInput = SMCParamStruct()
        infoInput.key = keyCode
        infoInput.data8 = UInt8(kSMCGetKeyInfo)
        guard let infoOutput = call(infoInput), infoOutput.keyInfo.dataSize > 0 else { return nil }

        var readInput = SMCParamStruct()
        readInput.key = keyCode
        readInput.keyInfo.dataSize = infoOutput.keyInfo.dataSize
        readInput.data8 = UInt8(kSMCReadKey)
        guard let readOutput = call(readInput) else { return nil }

        let dataSize = Int(infoOutput.keyInfo.dataSize)
        let dataType = Self.fourCharString(infoOutput.keyInfo.dataType)
        let bytes = withUnsafeBytes(of: readOutput.bytes) { Array($0.prefix(dataSize)) }
        return Self.decode(bytes: bytes, type: dataType, size: dataSize)
    }

    private func call(_ input: SMCParamStruct) -> SMCParamStruct? {
        guard isOpen else { return nil }
        var input = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.size
        let result = withUnsafeMutablePointer(to: &output) { outPtr -> kern_return_t in
            withUnsafeMutablePointer(to: &input) { inPtr -> kern_return_t in
                IOConnectCallStructMethod(
                    connection,
                    UInt32(kSMCHandleYPCEvent),
                    inPtr,
                    MemoryLayout<SMCParamStruct>.size,
                    outPtr,
                    &outputSize
                )
            }
        }
        guard result == kIOReturnSuccess, output.result == 0 else { return nil }
        return output
    }

    private static func fourCharCode(_ key: String) -> UInt32? {
        let chars = Array(key.utf8)
        guard chars.count == 4 else { return nil }
        return chars.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }

    private static func fourCharString(_ code: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func decode(bytes: [UInt8], type: String, size: Int) -> Double? {
        guard !bytes.isEmpty else { return nil }
        switch type {
        case "flt ":
            guard size >= 4 else { return nil }
            var value: Float32 = 0
            withUnsafeMutableBytes(of: &value) { dest in
                dest.copyBytes(from: bytes.prefix(4))
            }
            return Double(value)
        case "ui8 ", "ui16", "ui32":
            var result: UInt64 = 0
            for byte in bytes.prefix(size) {
                result = (result << 8) | UInt64(byte)
            }
            return Double(result)
        default:
            // sp78 and similar fixed-point types: signed integer byte + fractional byte(s)/256.
            guard size >= 2 else { return nil }
            let intPart = Int8(bitPattern: bytes[0])
            let fracPart = Double(bytes[1]) / 256.0
            return Double(intPart) + fracPart
        }
    }

    deinit {
        if isOpen {
            IOServiceClose(connection)
        }
    }
}
