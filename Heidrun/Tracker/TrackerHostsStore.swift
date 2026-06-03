import Foundation
import Observation

/// User-curated list of tracker hosts the tracker browser queries.
/// Persists as JSON in `UserDefaults` under
/// `AppStorageKeys.trackerHosts`. Default-seeds with a single
/// `hltracker.com:5498` entry on first read so the out-of-box
/// experience yields immediate results.
///
/// Patterned after `RecentsStore`: an `@Observable @MainActor` class
/// owned by `TrackerHostsRegistry.shared`; views observe the singleton
/// so a write from the in-window editor is seen by every open tracker
/// surface without a re-init dance.
@Observable
@MainActor
final class TrackerHostsStore {
    private(set) var hosts: [TrackerHost] = []
    private let defaults: UserDefaults

    /// Exposed for the test suite to re-instantiate against the same
    /// suite. Production callers should always go through
    /// `TrackerHostsRegistry.shared`.
    var defaultsForTesting: UserDefaults { defaults }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hosts = Self.load(from: defaults)
    }

    func append(_ host: TrackerHost) {
        hosts.append(host)
        save()
    }

    func update(_ host: TrackerHost) {
        guard let index = hosts.firstIndex(where: { $0.id == host.id }) else { return }
        hosts[index] = host
        save()
    }

    func remove(_ id: TrackerHost.ID) {
        hosts.removeAll { $0.id == id }
        save()
    }

    /// Empty the list AND persist the empty state so the next read
    /// doesn't trigger the default seed. Used by the editor's "Remove
    /// All" action and by the test suite.
    func removeAll() {
        hosts = []
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(hosts)
            defaults.set(data, forKey: AppStorageKeys.trackerHosts)
        } catch {
            // Tracker config is best-effort — never crash the app.
        }
    }

    private static func load(from defaults: UserDefaults) -> [TrackerHost] {
        // `data(forKey:)` returns nil for the never-written case AND for
        // type mismatches (e.g. a stray non-Data value left by another
        // launch). Both should re-seed.
        guard let data = defaults.data(forKey: AppStorageKeys.trackerHosts) else {
            return defaultSeed()
        }
        // Distinguish "user wrote an empty list" from "malformed bytes":
        // an explicit `[]` decodes cleanly to an empty array, which we
        // must NOT re-seed. Only re-seed when decode throws.
        if let decoded = try? JSONDecoder().decode([TrackerHost].self, from: data) {
            return decoded
        }
        return defaultSeed()
    }

    private static func defaultSeed() -> [TrackerHost] {
        [
            TrackerHost(name: "hltracker", host: "hltracker.com", port: 5498, enabled: true)
        ]
    }
}
