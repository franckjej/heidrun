import Foundation
import HeidrunCore

/// Abstraction over `HotlineTrackerClient.fetchServers` so
/// `TrackerBrowserViewModel` can be unit-tested with a recording fake
/// that doesn't touch the network. One method, exact same signature as
/// the production helper.
protocol TrackerFetcher: Sendable {
    func fetchServers(
        host: String,
        port: UInt16
    ) async throws -> [TrackerServer]
}

/// Resolves the hidden per-tracker fetch timeout. Not exposed in
/// Settings; power users override via
/// `defaults write org.tastybytes.heidrun Heidrun.trackerTimeoutSeconds <seconds>`.
enum TrackerTimeoutDefaults {
    /// Used when the key is absent or set to a non-positive value.
    static let fallbackSeconds: Double = 20

    static func resolved(defaults: UserDefaults = .standard) -> Duration {
        guard defaults.object(forKey: AppStorageKeys.trackerTimeoutSeconds) != nil else {
            return .seconds(fallbackSeconds)
        }
        let seconds = defaults.double(forKey: AppStorageKeys.trackerTimeoutSeconds)
        return .seconds(seconds > 0 ? seconds : fallbackSeconds)
    }
}

/// Production fetcher: a thin wrapper around the HeidrunCore tracker
/// client. No retry / caching layered here — the VM owns refresh
/// semantics.
struct LiveTrackerFetcher: TrackerFetcher {
    /// Resolved once when the fetcher is constructed (i.e. per browser
    /// open), so a `defaults write` override takes effect on the next
    /// time the browser is opened.
    var timeout: Duration = TrackerTimeoutDefaults.resolved()

    func fetchServers(host: String, port: UInt16) async throws -> [TrackerServer] {
        try await HotlineTrackerClient.fetchServers(host: host, port: port, timeout: timeout)
    }
}
