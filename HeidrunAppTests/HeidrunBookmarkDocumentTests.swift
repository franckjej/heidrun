import Foundation
import Testing
import UniformTypeIdentifiers
import HeidrunCore
import HeidrunBookmarks
@testable import Heidrun

@Suite("HeidrunBookmarkDocument")
@MainActor
struct HeidrunBookmarkDocumentTests {
    private func sampleBookmark(
        name: String = "Tom's BBS",
        address: String = "hl.example.com",
        port: UInt16 = 5500,
        login: String = "bob",
        useTLS: Bool = false,
        pinnedCertificateSHA256: String? = nil,
        emoji: String? = nil,
        autoReconnect: AutoReconnectOverride = .inherit
    ) -> Bookmark {
        Bookmark(
            settings: ConnectionSettings(
                name: name,
                address: address,
                port: port,
                nickname: "Bob",
                login: login,
                icon: 42,
                useTLS: useTLS,
                pinnedCertificateSHA256: pinnedCertificateSHA256,
                emoji: emoji
            ),
            autoReconnect: autoReconnect
        )
    }

    @Test("untitled init has sensible defaults")
    func untitledDefaults() {
        let document = HeidrunBookmarkDocument()
        #expect(document.bookmark.settings.address.isEmpty)
        #expect(document.bookmark.settings.port == 5500)
        #expect(document.bookmark.settings.useTLS == false)
        #expect(document.bookmark.settings.pinnedCertificateSHA256 == nil)
        #expect(document.bookmark.autoReconnect == .inherit)
    }

    @Test("snapshot returns the live bookmark unchanged")
    func snapshotReturnsLiveBookmark() throws {
        let document = HeidrunBookmarkDocument()
        document.bookmark = sampleBookmark(
            useTLS: true,
            pinnedCertificateSHA256: "ABC123",
            autoReconnect: .alwaysOn
        )
        let snapshot = try document.snapshot(contentType: .heidrunBookmark)
        #expect(snapshot.settings.address == "hl.example.com")
        #expect(snapshot.settings.useTLS == true)
        #expect(snapshot.settings.pinnedCertificateSHA256 == "ABC123")
        #expect(snapshot.autoReconnect == .alwaysOn)
    }

    @Test("encode + decode round-trips every persistent field")
    func encodeDecodeRoundTrip() throws {
        let original = sampleBookmark(
            useTLS: true,
            pinnedCertificateSHA256: "DEADBEEF",
            emoji: "🦊",
            autoReconnect: .alwaysOff
        )
        let data = try HeidrunBookmarkDocument.encodeBookmark(original)
        let decoded = try HeidrunBookmarkDocument.decodeBookmark(from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.settings.name == original.settings.name)
        #expect(decoded.settings.address == original.settings.address)
        #expect(decoded.settings.port == original.settings.port)
        #expect(decoded.settings.login == original.settings.login)
        #expect(decoded.settings.nickname == original.settings.nickname)
        #expect(decoded.settings.icon == original.settings.icon)
        #expect(decoded.settings.useTLS == original.settings.useTLS)
        #expect(decoded.settings.pinnedCertificateSHA256 == original.settings.pinnedCertificateSHA256)
        #expect(decoded.settings.emoji == original.settings.emoji)
        #expect(decoded.autoReconnect == original.autoReconnect)
    }

    @Test("encoded payload has sorted keys (stable byte order)")
    func encoderStability() throws {
        let original = sampleBookmark()
        let firstEncode = try HeidrunBookmarkDocument.encodeBookmark(original)
        let secondEncode = try HeidrunBookmarkDocument.encodeBookmark(original)
        #expect(firstEncode == secondEncode)
    }

    @Test("decode throws on empty data")
    func decodeEmptyThrows() {
        #expect(throws: Error.self) {
            _ = try HeidrunBookmarkDocument.decodeBookmark(from: Data())
        }
    }

    @Test("decode throws on malformed JSON")
    func decodeMalformedThrows() {
        let garbage = Data("{not json}".utf8)
        #expect(throws: Error.self) {
            _ = try HeidrunBookmarkDocument.decodeBookmark(from: garbage)
        }
    }

    @Test("settings convenience setter mirrors bookmark.settings")
    func settingsConvenienceSetter() {
        let document = HeidrunBookmarkDocument()
        let newSettings = sampleBookmark(address: "foo.example", port: 5510).settings
        document.settings = newSettings
        #expect(document.bookmark.settings.address == "foo.example")
        #expect(document.bookmark.settings.port == 5510)
    }

    @Test("updateBookmark registers undo with the supplied manager")
    func updateBookmarkRegistersUndo() {
        let document = HeidrunBookmarkDocument()
        let originalBookmark = document.bookmark
        let manager = UndoManager()
        manager.disableUndoRegistration()
        manager.enableUndoRegistration()

        let edited = sampleBookmark(address: "edited.example")
        document.updateBookmark(edited, undoManager: manager)

        #expect(document.bookmark.settings.address == "edited.example")
        #expect(manager.canUndo)

        manager.undo()
        #expect(document.bookmark == originalBookmark)
        #expect(manager.canRedo)

        manager.redo()
        #expect(document.bookmark.settings.address == "edited.example")
    }

    @Test("updateBookmark is a no-op when the value is unchanged")
    func updateBookmarkSkipsIdenticalValue() {
        let document = HeidrunBookmarkDocument()
        let manager = UndoManager()
        manager.disableUndoRegistration()
        manager.enableUndoRegistration()

        // Mutating to the same value must NOT mark the doc edited —
        // otherwise opening a saved bookmark and clicking Connect
        // without changing anything would falsely enable Save.
        document.updateBookmark(document.bookmark, undoManager: manager)
        #expect(!manager.canUndo)
    }
}
