import Foundation

/// Makes an outbound HTTPS call to a third-party IP-lookup service.
/// Only ever invoked when `AppSettings.publicIPEnabled` is true (default
/// false), and on its own low-frequency cadence — never at the 1s network
/// poll rate.
public actor PublicIPFetcher: SystemMetricProvider {
    public init() {}

    public func poll() async -> String? {
        guard let url = URL(string: "https://api.ipify.org?format=text") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}
