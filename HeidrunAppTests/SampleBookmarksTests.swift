import Foundation
import Testing
import HeidrunCore
import HeidrunBookmarks
@testable import Heidrun

@MainActor
@Suite("SampleBookmarks")
struct SampleBookmarksTests {
    private func emptyStore() -> BookmarkStore {
        let suite = "sample-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        // Pin a per-test tmpdir so the file-backed store doesn't read
        // (or write) the user's real bookmarks folder during tests.
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sample-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        return BookmarkStore(defaults: defaults, bookmarksDirectoryURL: tmpDir)
    }

    @Test("seeds sample bookmarks into an empty isolated store")
    func seedsWhenIsolatedAndEmpty() {
        let store = emptyStore()
        let seeded = SampleBookmarks.seedIfNeeded(into: store, isIsolated: true)
        #expect(seeded == true)
        #expect(store.bookmarks.count == SampleBookmarks.all.count)
        #expect(store.bookmarks.contains { $0.settings.address == "hl.test" })
    }

    @Test("does not seed when not isolated")
    func skipsWhenNotIsolated() {
        let store = emptyStore()
        let seeded = SampleBookmarks.seedIfNeeded(into: store, isIsolated: false)
        #expect(seeded == false)
        #expect(store.bookmarks.isEmpty)
    }

    @Test("does not seed when the store already has bookmarks")
    func skipsWhenNotEmpty() {
        let store = emptyStore()
        store.add(Bookmark(settings: ConnectionSettings(name: "Existing", address: "real.example")))
        let seeded = SampleBookmarks.seedIfNeeded(into: store, isIsolated: true)
        #expect(seeded == false)
        #expect(store.bookmarks.count == 1)
    }

    @Test("a sample bookmark carries the TLS flag")
    func sampleHasTLSEntry() {
        #expect(SampleBookmarks.all.contains { $0.settings.useTLS })
    }
}
