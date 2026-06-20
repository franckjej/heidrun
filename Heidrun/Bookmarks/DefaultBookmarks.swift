import Foundation
import HeidrunCore
import HeidrunBookmarks

/// The built-in "Heidrun's Inn" bookmark seeded into a fresh install's
/// sidebar on first launch, so new users have a server to connect to out of
/// the box. Unlike `SampleBookmarks` (dev-only, gated on
/// `AppDataEnvironment.isIsolated`), this ships in Release.
enum DefaultBookmarks {
    /// Persistent "already seeded" flag. Seeding is gated on this rather than
    /// on an empty roster, so deleting the bookmark never resurrects it on
    /// the next launch.
    static let didSeedDefaultsKey = "Heidrun.didSeedDefaultBookmark"

    /// The official public server.
    static var heidrunsInn: Bookmark {
        Bookmark(settings: ConnectionSettings(
            name: "Heidrun's Inn",
            address: "tastybytes.org",
            port: 5500,
            nickname: "Heidrunner",
            login: "guest"
        ))
    }

    /// Seed the default bookmark exactly once, and only into a never-seeded,
    /// empty store (a genuine fresh install). The flag is set on the first
    /// run regardless, so an upgrader who already has bookmarks never gets it
    /// injected, and a user who deletes it never sees it return. Returns
    /// whether it actually added the bookmark.
    @MainActor
    @discardableResult
    static func seedIfNeeded(into store: BookmarkStore, defaults: UserDefaults) -> Bool {
        guard !defaults.bool(forKey: didSeedDefaultsKey) else { return false }
        defaults.set(true, forKey: didSeedDefaultsKey)
        guard store.bookmarks.isEmpty else { return false }
        store.add(heidrunsInn)
        return true
    }
}
