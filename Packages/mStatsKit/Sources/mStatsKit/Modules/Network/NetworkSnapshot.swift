import Foundation

public enum NetworkConnectionType: Sendable {
    case wifi, wired, cellular, other, unavailable
}

public struct NetworkSnapshot: Sendable {
    public let downloadBytesPerSec: Double
    public let uploadBytesPerSec: Double
    public let peakDownloadBytesPerSec: Double
    public let peakUploadBytesPerSec: Double
    public let localIPAddresses: [String]
    public let connectionType: NetworkConnectionType
    /// nil unless the user opted in (AppSettings.publicIPEnabled) — see PublicIPFetcher.
    public let publicIPAddress: String?

    public static let empty = NetworkSnapshot(
        downloadBytesPerSec: 0, uploadBytesPerSec: 0,
        peakDownloadBytesPerSec: 0, peakUploadBytesPerSec: 0,
        localIPAddresses: [], connectionType: .unavailable, publicIPAddress: nil
    )
}
