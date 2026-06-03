import Foundation
import HeidrunCore

/// Persists which servers Heidrun was actively connected to at the moment
/// of quit, so the next launch can reopen them. Stored as JSON under a
/// single `UserDefaults` key — small enough that the read/write round
/// trip is negligible, and `ConnectionSettings` is already `Codable`.
///
/// Only the per-connection metadata is stored here. The matching
/// password (when "Remember password" was on) lives in the Keychain and
/// is looked up by `(address, port, login)` during restore.
struct SessionRestorationStore {
    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = AppStorageKeys.sessionRestoration
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    /// Replace any previously saved snapshot with `settings`. An empty
    /// array clears the key entirely so the next launch sees a clean
    /// state rather than reading `[]` and short-circuiting.
    func save(_ settings: [ConnectionSettings]) {
        guard !settings.isEmpty else {
            defaults.removeObject(forKey: storageKey)
            return
        }
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: storageKey)
        } catch {
            // Best-effort: restoration is a convenience, not load-bearing.
            // A failed encode just means the next launch won't restore.
        }
    }

    /// Read the saved snapshot. Returns an empty array when there's
    /// nothing stored or the payload can't be decoded (e.g. the
    /// `ConnectionSettings` schema changed since the snapshot was
    /// written).
    func load() -> [ConnectionSettings] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([ConnectionSettings].self, from: data)) ?? []
    }

    /// Drop the saved snapshot. Called when the user disables the
    /// "reopen on launch" preference so a stale snapshot doesn't sit
    /// around waiting to ambush them after a future re-enable.
    func clear() {
        defaults.removeObject(forKey: storageKey)
    }
}
