import Foundation
import Testing
import HeidrunCore
import HeidrunBookmarks
@testable import Heidrun

@MainActor
@Suite("DefaultBookmarks")
struct DefaultBookmarksTests {
    /// A store + defaults isolated to this test, so seeding never touches
    /// the real app's bookmarks directory or standard UserDefaults.
    private struct Fixture {
        let store: BookmarkStore
        let defaults: UserDefaults
        let suiteName: String
        let directory: URL

        func tearDown() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func makeFixture() -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bm-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "test.defaultbookmarks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = BookmarkStore(defaults: defaults, bookmarksDirectoryURL: directory)
        return Fixture(store: store, defaults: defaults, suiteName: suiteName, directory: directory)
    }

    @Test("seeds Heidrun's Inn into a fresh, never-seeded store")
    func seedsFreshInstall() {
        let fixture = makeFixture()
        defer { fixture.tearDown() }

        let seeded = DefaultBookmarks.seedIfNeeded(into: fixture.store, defaults: fixture.defaults)
        #expect(seeded)
        #expect(fixture.store.bookmarks.count == 1)
        let mark = fixture.store.bookmarks.first
        #expect(mark?.settings.name == "Heidrun's Inn")
        #expect(mark?.settings.address == "tastybytes.org")
        #expect(mark?.settings.port == 5500)
        #expect(mark?.settings.nickname == "Heidrunner")
        #expect(mark?.settings.login == "guest")
        #expect(mark?.settings.useTLS == false)
        #expect(fixture.defaults.bool(forKey: DefaultBookmarks.didSeedDefaultsKey))
    }

    @Test("never resurrects after the user deletes it")
    func doesNotResurrectAfterDeletion() {
        let fixture = makeFixture()
        defer { fixture.tearDown() }

        #expect(DefaultBookmarks.seedIfNeeded(into: fixture.store, defaults: fixture.defaults))
        if let id = fixture.store.bookmarks.first?.id {
            fixture.store.remove(id: id)
        }
        #expect(fixture.store.bookmarks.isEmpty)

        let seededAgain = DefaultBookmarks.seedIfNeeded(into: fixture.store, defaults: fixture.defaults)
        #expect(!seededAgain)
        #expect(fixture.store.bookmarks.isEmpty)   // stays gone
    }

    @Test("does not inject into a user who already has bookmarks")
    func skipsExistingRoster() {
        let fixture = makeFixture()
        defer { fixture.tearDown() }

        let existing = Bookmark(settings: ConnectionSettings(
            name: "Mine",
            address: "my.test",
            port: 5500
        ))
        fixture.store.add(existing)

        let seeded = DefaultBookmarks.seedIfNeeded(into: fixture.store, defaults: fixture.defaults)
        #expect(!seeded)
        #expect(fixture.store.bookmarks.count == 1)
        #expect(fixture.store.bookmarks.first?.settings.name == "Mine")
        // Flag is still set, so it won't try again on the next launch either.
        #expect(fixture.defaults.bool(forKey: DefaultBookmarks.didSeedDefaultsKey))
    }
}
