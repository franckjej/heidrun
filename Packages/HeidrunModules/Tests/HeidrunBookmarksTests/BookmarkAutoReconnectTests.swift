import Foundation
import Testing
import HeidrunCore
@testable import HeidrunBookmarks

@Suite("Bookmark.autoReconnect")
struct BookmarkAutoReconnectTests {

    private func sampleSettings() -> ConnectionSettings {
        ConnectionSettings(
            name: "Sample",
            address: "sample.example.com",
            port: 5500,
            nickname: "tester",
            login: ""
        )
    }

    @Test("default value is .inherit")
    func defaultValueIsInherit() {
        let bookmark = Bookmark(settings: sampleSettings())
        #expect(bookmark.autoReconnect == .inherit)
    }

    @Test("encoding and decoding round-trips .alwaysOn")
    func roundTripAlwaysOn() throws {
        let original = Bookmark(settings: sampleSettings(), autoReconnect: .alwaysOn)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Bookmark.self, from: data)
        #expect(decoded.autoReconnect == .alwaysOn)
        #expect(decoded.settings == original.settings)
        #expect(decoded.id == original.id)
    }

    @Test("decoding a v1 JSON blob without the key yields .inherit")
    func decodingV1JsonMigratesToInherit() throws {
        // Hand-crafted JSON shaped like the v1 store output: id + settings,
        // no `autoReconnect` field. ConnectionSettings is encoded as its
        // synthesized keyed container.
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
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

        let decoded = try JSONDecoder().decode(Bookmark.self, from: json)
        #expect(decoded.autoReconnect == .inherit)
        #expect(decoded.settings.address == "old.example.com")
    }
}
