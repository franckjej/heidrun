import Foundation
import Observation
import HeidrunCore

/// Persists the user's most recently used connection bookmarks. Capped at
/// 10 entries, deduplicated by `(name, address, port, login)`, and backed
/// by `UserDefaults`. **Never stores passwords** — `ConnectionSettings`
/// has no password field, so this is a structural guarantee.
@Observable
@MainActor
final class RecentsStore {
    static let storageKey = "Heidrun.recents"
    static let maxEntries = 10

    private(set) var entries: [ConnectionSettings] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.entries = Self.load(from: defaults)
    }

    func record(_ settings: ConnectionSettings) {
        entries.removeAll { isSameBookmark($0, settings) }
        entries.insert(settings, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
        save()
    }

    /// Empty the in-memory list and persist the cleared state. Call on
    /// `RecentsRegistry.shared` — that's the instance every UI surface
    /// observes, so clearing it propagates to the connect form, the
    /// File-menu submenu, and anywhere else that reads `entries`.
    func clear() {
        entries = []
        save()
    }

    private func isSameBookmark(_ a: ConnectionSettings, _ b: ConnectionSettings) -> Bool {
        a.name == b.name && a.address == b.address && a.port == b.port && a.login == b.login
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            defaults.set(data, forKey: Self.storageKey)
        } catch {
            // Recents is best-effort — never crash the app over it.
        }
    }

    private static func load(from defaults: UserDefaults) -> [ConnectionSettings] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([ConnectionSettings].self, from: data)) ?? []
    }
}
