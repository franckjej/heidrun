import Foundation
import Testing
import HeidrunCore
@testable import HeidrunBookmarks

@Suite("Bookmark.menuShortcutSlot")
struct BookmarkMenuShortcutModelTests {

    private func sampleSettings() -> ConnectionSettings {
        ConnectionSettings(
            name: "Sample",
            address: "sample.example.com",
            port: 5500,
            nickname: "tester",
            login: ""
        )
    }

    private func blob(slotFragment: String) -> Data {
        """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "autoReconnect": "inherit",
          \(slotFragment)
          "settings": {
            "name": "Old",
            "address": "old.example.com",
            "port": 5500,
            "nickname": "tester",
            "login": "",
            "icon": 0,
            "useDefaultUserInfo": true,
            "autoConnectFavorite": false,
            "assignFavoriteShortcut": false
          }
        }
        """.data(using: .utf8)!
    }

    @Test("default is nil")
    func defaultIsNil() {
        #expect(Bookmark(settings: sampleSettings()).menuShortcutSlot == nil)
    }

    @Test("round-trips a slot")
    func roundTrip() throws {
        let original = Bookmark(settings: sampleSettings(), menuShortcutSlot: 3)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Bookmark.self, from: data)
        #expect(decoded.menuShortcutSlot == 3)
    }

    @Test("missing key decodes as nil")
    func missingKeyIsNil() throws {
        let decoded = try JSONDecoder().decode(Bookmark.self, from: blob(slotFragment: ""))
        #expect(decoded.menuShortcutSlot == nil)
    }

    @Test("out-of-range slot decodes as nil", arguments: [0, 10, -1])
    func outOfRangeIsNil(slot: Int) throws {
        let json = blob(slotFragment: "\"menuShortcutSlot\": \(slot),")
        let decoded = try JSONDecoder().decode(Bookmark.self, from: json)
        #expect(decoded.menuShortcutSlot == nil)
    }
}

@Suite("BookmarkStore menu shortcut uniqueness")
@MainActor
struct BookmarkStoreMenuShortcutTests {

    private let directoryURL: URL
    private let suiteName: String
    private let defaults: UserDefaults

    init() {
        suiteName = "BookmarkStoreMenuShortcutTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func makeStore() -> BookmarkStore {
        BookmarkStore(defaults: defaults, bookmarksDirectoryURL: directoryURL)
    }

    private func teardown() {
        defaults.removePersistentDomain(forName: suiteName)
        let prefsPath = ("~/Library/Preferences/\(suiteName).plist" as NSString).expandingTildeInPath
        try? FileManager.default.removeItem(atPath: prefsPath)
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private func makeBookmark(_ name: String, slot: Int? = nil) -> Bookmark {
        Bookmark(
            settings: ConnectionSettings(
                name: name,
                address: "\(name.lowercased()).example.com",
                port: 5500,
                nickname: "tester",
                login: ""
            ),
            menuShortcutSlot: slot
        )
    }

    @Test("add with a taken slot steals it and persists the loser")
    func addSteals() {
        defer { teardown() }
        let store = makeStore()
        let first = makeBookmark("Alpha", slot: 2)
        let second = makeBookmark("Beta", slot: 2)
        store.add(first)
        store.add(second)
        #expect(store.bookmarks.first { $0.id == first.id }?.menuShortcutSlot == nil)
        #expect(store.bookmarks.first { $0.id == second.id }?.menuShortcutSlot == 2)
        let reloaded = makeStore()
        #expect(reloaded.bookmarks.first { $0.id == first.id }?.menuShortcutSlot == nil)
    }

    @Test("update with a taken slot steals it")
    func updateSteals() {
        defer { teardown() }
        let store = makeStore()
        let first = makeBookmark("Alpha", slot: 5)
        var second = makeBookmark("Beta")
        store.add(first)
        store.add(second)
        second.menuShortcutSlot = 5
        store.update(second)
        #expect(store.bookmarks.first { $0.id == first.id }?.menuShortcutSlot == nil)
        #expect(store.bookmarks.first { $0.id == second.id }?.menuShortcutSlot == 5)
    }

    @Test("updating a bookmark to its own slot keeps it")
    func updateOwnSlot() {
        defer { teardown() }
        let store = makeStore()
        let first = makeBookmark("Alpha", slot: 1)
        store.add(first)
        store.update(first)
        #expect(store.bookmarks.first?.menuShortcutSlot == 1)
    }

    @Test("replaceAll keeps the first duplicate in roster order")
    func replaceAllNormalizes() {
        defer { teardown() }
        let store = makeStore()
        let first = makeBookmark("Alpha", slot: 4)
        let second = makeBookmark("Beta", slot: 4)
        let third = makeBookmark("Gamma", slot: 7)
        store.replaceAll(with: [first, second, third])
        #expect(store.bookmarks.map(\.menuShortcutSlot) == [4, nil, 7])
    }

    @Test("load normalizes duplicates written straight to disk")
    func loadNormalizes() throws {
        defer { teardown() }
        let first = makeBookmark("Alpha", slot: 9)
        let second = makeBookmark("Beta", slot: 9)
        for mark in [first, second] {
            let url = directoryURL.appendingPathComponent("\(mark.id.uuidString).heidrunbookmark")
            try JSONEncoder().encode(mark).write(to: url)
        }
        defaults.set([first.id.uuidString, second.id.uuidString], forKey: BookmarkStore.orderStorageKey)
        let store = makeStore()
        #expect(store.bookmarks.map(\.menuShortcutSlot) == [9, nil])
    }
}
