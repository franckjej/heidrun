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
