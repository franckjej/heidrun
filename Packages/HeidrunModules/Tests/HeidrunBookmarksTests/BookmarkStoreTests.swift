import Foundation
import Testing
import HeidrunCore
@testable import HeidrunBookmarks

@Suite("BookmarkStore")
@MainActor
struct BookmarkStoreTests {

    /// Scratch fixture: a fresh `BookmarkStore` pinned to a
    /// per-test tmpdir so the disk side-effects don't leak between
    /// tests (or into the user's real bookmarks folder). UserDefaults
    /// remains a UUID-suffixed suite so the legacy-migration test
    /// can still seed a synthetic blob there.
    @MainActor
    private struct Scratch {
        let store: BookmarkStore
        let defaults: UserDefaults
        let suite: String
        let bookmarksDirectoryURL: URL
        private let prefsPath: String

        init() {
            let suiteName = "BookmarkStoreTests-\(UUID().uuidString)"
            let userDefaults = UserDefaults(suiteName: suiteName)!
            userDefaults.removePersistentDomain(forName: suiteName)
            self.defaults = userDefaults
            self.suite = suiteName
            self.prefsPath = ("~/Library/Preferences/\(suiteName).plist" as NSString)
                .expandingTildeInPath

            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("BookmarkStoreTests-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
            self.bookmarksDirectoryURL = tmpDir

            self.store = BookmarkStore(
                defaults: userDefaults,
                bookmarksDirectoryURL: tmpDir
            )
        }

        /// Make a fresh store reading from the same tmpdir — used to
        /// verify that an `add` / `update` actually hit disk and would
        /// survive a relaunch.
        func reloadedStore() -> BookmarkStore {
            BookmarkStore(
                defaults: defaults,
                bookmarksDirectoryURL: bookmarksDirectoryURL
            )
        }

        func teardown() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(atPath: prefsPath)
            try? FileManager.default.removeItem(at: bookmarksDirectoryURL)
        }
    }

    private func makeScratch() -> Scratch {
        Scratch()
    }

    private func makeBookmark(_ name: String = "Test", id: UUID = UUID()) -> Bookmark {
        Bookmark(
            id: id,
            settings: ConnectionSettings(
                name: name,
                address: "\(name.lowercased()).example.com",
                port: 5500,
                nickname: "tester",
                login: ""
            )
        )
    }

    @Test("init starts empty when nothing is persisted")
    func initStartsEmpty() {
        let scratch = makeScratch()
        defer { scratch.teardown() }
        #expect(scratch.store.bookmarks.isEmpty)
    }

    @Test("add appends and persists to disk")
    func addAppendsAndPersists() {
        let scratch = makeScratch()
        defer { scratch.teardown() }
        let mark = makeBookmark()
        scratch.store.add(mark)
        #expect(scratch.store.bookmarks.count == 1)
        #expect(scratch.store.bookmarks.first?.id == mark.id)

        // Fresh store reading the same tmpdir reloads the bookmark
        // from its file — proves the write actually landed.
        let reloaded = scratch.reloadedStore()
        #expect(reloaded.bookmarks.first?.id == mark.id)
    }

    @Test("add with an existing id behaves as update (no duplicate)")
    func addWithExistingIdReplacesInPlace() {
        let scratch = makeScratch()
        defer { scratch.teardown() }
        let identifier = UUID()
        let first = makeBookmark("First", id: identifier)
        let second = makeBookmark("Second", id: identifier)
        scratch.store.add(first)
        scratch.store.add(second)
        #expect(scratch.store.bookmarks.count == 1)
        #expect(scratch.store.bookmarks.first?.settings.name == "Second")
    }

    @Test("update replaces by id; no-op when id is unknown")
    func updateReplacesByID() {
        let scratch = makeScratch()
        defer { scratch.teardown() }
        let mark = makeBookmark("Original")
        scratch.store.add(mark)

        var renamed = mark
        renamed.settings.name = "Renamed"
        scratch.store.update(renamed)
        #expect(scratch.store.bookmarks.first?.settings.name == "Renamed")

        // Unknown id → no-op.
        let stranger = makeBookmark("Stranger")
        scratch.store.update(stranger)
        #expect(scratch.store.bookmarks.count == 1)
    }

    @Test("remove drops the matching id and its file; no-op when not found")
    func removeDropsByID() {
        let scratch = makeScratch()
        defer { scratch.teardown() }
        let mark = makeBookmark()
        scratch.store.add(mark)
        let path = scratch.store.url(for: mark)?.path
        scratch.store.remove(id: mark.id)
        #expect(scratch.store.bookmarks.isEmpty)
        if let path {
            #expect(!FileManager.default.fileExists(atPath: path))
        }

        // Unknown id → no throw, no change.
        scratch.store.remove(id: UUID())
        #expect(scratch.store.bookmarks.isEmpty)
    }

    @Test("contains reports id presence")
    func containsReportsPresence() {
        let scratch = makeScratch()
        defer { scratch.teardown() }
        let mark = makeBookmark()
        scratch.store.add(mark)
        #expect(scratch.store.contains(id: mark.id))
        #expect(!scratch.store.contains(id: UUID()))
    }

    @Test("bookmark(matching:) keys on (name, address, port, login)")
    func matchingFindsByQuadruple() {
        let scratch = makeScratch()
        defer { scratch.teardown() }
        let mark = makeBookmark()
        scratch.store.add(mark)
        #expect(scratch.store.bookmark(matching: mark.settings)?.id == mark.id)

        // Differ in any one of the four → no match.
        var different = mark.settings
        different.port = 5501
        #expect(scratch.store.bookmark(matching: different) == nil)
    }

    @Test("replaceAll swaps the roster and clears obsolete files")
    func replaceAllSwapsAndPersists() {
        let scratch = makeScratch()
        defer { scratch.teardown() }
        let original = makeBookmark("A")
        scratch.store.add(original)
        let replacements = [makeBookmark("B"), makeBookmark("C")]
        scratch.store.replaceAll(with: replacements)
        #expect(scratch.store.bookmarks.map(\.settings.name) == ["B", "C"])

        // The original bookmark's file should be gone.
        let originalURL = scratch.bookmarksDirectoryURL
            .appendingPathComponent("\(original.id.uuidString).heidrunbookmark")
        #expect(!FileManager.default.fileExists(atPath: originalURL.path))

        let reloaded = scratch.reloadedStore()
        #expect(Set(reloaded.bookmarks.map(\.settings.name)) == Set(["B", "C"]))
    }

    @Test("persisted file never contains a password field")
    func persistedFileHasNoPasswordField() throws {
        let scratch = makeScratch()
        defer { scratch.teardown() }
        let mark = makeBookmark("Carpe")
        scratch.store.add(mark)

        let url = try #require(scratch.store.url(for: mark))
        let data = try Data(contentsOf: url)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.lowercased().contains("password"))
    }

    @Test("bookmark(forAddress:port:) returns nil when the store is empty")
    func bookmarkForAddress_returnsNilWhenStoreEmpty() {
        let scratch = makeScratch()
        defer { scratch.teardown() }
        #expect(scratch.store.bookmark(forAddress: "x.example.com", port: 5500) == nil)
    }

    @Test("bookmark(forAddress:port:) matches on address + port, ignoring login + name")
    func bookmarkForAddress_findsMatchByAddressAndPort() {
        let scratch = makeScratch()
        defer { scratch.teardown() }
        let mark = Bookmark(
            id: UUID(),
            settings: ConnectionSettings(
                name: "My Server",
                address: "tracker.example.com",
                port: 5500,
                nickname: "tester",
                login: "alice"
            )
        )
        scratch.store.add(mark)
        let found = scratch.store.bookmark(forAddress: "tracker.example.com", port: 5500)
        #expect(found?.settings.login == "alice")
    }

    @Test("bookmark(forAddress:port:) is case-insensitive on the address")
    func bookmarkForAddress_caseInsensitiveAddress() {
        let scratch = makeScratch()
        defer { scratch.teardown() }
        let mark = Bookmark(
            id: UUID(),
            settings: ConnectionSettings(name: "S", address: "hosting.tastybytes.org", port: 5500, login: "admin")
        )
        scratch.store.add(mark)
        #expect(scratch.store.bookmark(forAddress: "Hosting.TastyBytes.ORG", port: 5500)?.settings.login == "admin")
    }

    @Test("bookmark(forAddress:port:) misses when the port differs")
    func bookmarkForAddress_missesOnPortMismatch() {
        let scratch = makeScratch()
        defer { scratch.teardown() }
        let mark = Bookmark(
            id: UUID(),
            settings: ConnectionSettings(name: "S", address: "p.example.com", port: 5500, login: "u")
        )
        scratch.store.add(mark)
        #expect(scratch.store.bookmark(forAddress: "p.example.com", port: 5502) == nil)
    }

    @Test("legacy UserDefaults blob migrates to per-file storage on first init")
    func legacyDefaultsMigration() throws {
        // Seed a per-test suite WITH a legacy blob, then init a fresh
        // store and verify it adopts the entries + clears the key.
        let suiteName = "BookmarkStoreMigration-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BookmarkStoreMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: tmpDir)
        }

        let legacy = [
            makeBookmark("Legacy A"),
            makeBookmark("Legacy B")
        ]
        let legacyData = try JSONEncoder().encode(legacy)
        defaults.set(legacyData, forKey: BookmarkStore.storageKey)

        let store = BookmarkStore(defaults: defaults, bookmarksDirectoryURL: tmpDir)
        #expect(Set(store.bookmarks.map(\.settings.name)) == Set(["Legacy A", "Legacy B"]))
        // Migration is one-shot — the legacy key should be cleared.
        #expect(defaults.data(forKey: BookmarkStore.storageKey) == nil)

        // And the files actually landed on disk.
        let reloaded = BookmarkStore(defaults: defaults, bookmarksDirectoryURL: tmpDir)
        #expect(Set(reloaded.bookmarks.map(\.settings.name)) == Set(["Legacy A", "Legacy B"]))
    }

    @Test("url(for:) returns nil for an unpersisted bookmark, the file URL otherwise")
    func urlForBookmark() {
        let scratch = makeScratch()
        defer { scratch.teardown() }
        let mark = makeBookmark()
        #expect(scratch.store.url(for: mark) == nil)
        scratch.store.add(mark)
        let url = scratch.store.url(for: mark)
        #expect(url != nil)
        #expect(url?.pathExtension == "heidrunbookmark")
        #expect(url?.lastPathComponent.contains(mark.id.uuidString) == true)
    }
}
