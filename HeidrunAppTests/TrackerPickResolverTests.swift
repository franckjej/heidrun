import Foundation
import Testing
@testable import Heidrun
@testable import HeidrunBookmarks
import HeidrunCore
import CommonTools

@MainActor
@Suite("TrackerPickResolver.resolveLogin")
struct TrackerPickResolverTests {
    @Test("prefers the bookmark login over a keychain entry")
    func prefersBookmark_overKeychain() throws {
        let address = "resolver-\(UUID().uuidString).example"
        // Seed a keychain entry under a different login...
        let key = KeychainPasswordStore.Key.canonical(address: address, port: 5500, login: "keychainuser")
        defer { try? KeychainPasswordStore.delete(for: key) }
        try KeychainPasswordStore.save("secret", for: key)
        // ...and a bookmark with the authoritative login.
        let mark = Bookmark(
            id: UUID(),
            settings: ConnectionSettings(name: "S", address: address, port: 5500, login: "bookmarkuser")
        )
        BookmarkRegistry.shared.add(mark)
        defer { BookmarkRegistry.shared.remove(id: mark.id) }

        #expect(TrackerPickResolver.resolveLogin(address: address, port: 5500) == "bookmarkuser")
    }

    @Test("falls back to the keychain login when no bookmark matches")
    func fallsBackToKeychain_whenNoBookmark() throws {
        let address = "resolver-\(UUID().uuidString).example"
        let key = KeychainPasswordStore.Key.canonical(address: address, port: 5500, login: "keychainuser")
        defer { try? KeychainPasswordStore.delete(for: key) }
        try KeychainPasswordStore.save("secret", for: key)

        #expect(TrackerPickResolver.resolveLogin(address: address, port: 5500) == "keychainuser")
    }

    @Test("returns empty when nothing is saved")
    func returnsEmpty_whenNothingSaved() {
        let address = "resolver-\(UUID().uuidString).example"
        #expect(TrackerPickResolver.resolveLogin(address: address, port: 5500).isEmpty)
    }
}
