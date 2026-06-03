import HeidrunCore
import HeidrunBookmarks

/// Throwaway bookmarks seeded into an isolated debug run so the sidebar
/// isn't empty during development. Never used in production / Release —
/// the seed is gated on `AppDataEnvironment.isIsolated` at launch.
enum SampleBookmarks {
    /// The fake roster. Addresses use the reserved `.test` TLD so they
    /// can never resolve to a real host. No passwords.
    static var all: [Bookmark] {
        [
            Bookmark(settings: ConnectionSettings(name: "Test BBS", address: "hl.test", port: 5500)),
            Bookmark(settings: ConnectionSettings(name: "Cipher BBS", address: "tls.test", port: 5502, useTLS: true)),
            Bookmark(settings: ConnectionSettings(name: "Guest Board", address: "guest.test", port: 5500))
        ]
    }

    /// Populate `store` with the sample roster only when running isolated
    /// and the store is empty. Returns whether it seeded. No-op otherwise,
    /// so a developer's own test bookmarks in the isolated suite are never
    /// clobbered.
    @MainActor
    @discardableResult
    static func seedIfNeeded(into store: BookmarkStore, isIsolated: Bool) -> Bool {
        guard isIsolated, store.bookmarks.isEmpty else { return false }
        for mark in all { store.add(mark) }
        return true
    }
}
