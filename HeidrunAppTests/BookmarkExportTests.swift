import Foundation
import Testing
import HeidrunCore
import HeidrunBookmarks
@testable import Heidrun

@Suite("BookmarkExport")
struct BookmarkExportTests {
    private func sampleBookmark(
        name: String = "Tom's BBS",
        address: String = "hl.example.com",
        port: UInt16 = 5500,
        login: String = "bob"
    ) -> Bookmark {
        Bookmark(settings: ConnectionSettings(name: name, address: address, port: port, login: login))
    }

    @Test("archiveData round-trips bookmarks without writing any password")
    func archiveDataHasNoPasswords() throws {
        let marks = [
            sampleBookmark(name: "A", address: "a.example"),
            sampleBookmark(name: "B", address: "b.example")
        ]
        let data = try BookmarkExport.archiveData(for: marks)
        var passwordWrites = 0
        let restored = try BookmarkArchiver.unarchive(data) { _, _ in passwordWrites += 1 }
        #expect(restored.count == 2)
        #expect(restored.map(\.settings.address) == ["a.example", "b.example"])
        #expect(passwordWrites == 0)
    }

    @Test("suggestedFileName uses the single bookmark's name")
    func fileNameSingleName() {
        let export = BookmarkExport(bookmarks: [sampleBookmark(name: "Tom's BBS")])
        #expect(export.suggestedFileName == "Tom's BBS")
    }

    @Test("suggestedFileName falls back to address when name is blank")
    func fileNameBlankFallsBackToAddress() {
        let export = BookmarkExport(bookmarks: [sampleBookmark(name: "", address: "hl.example.com")])
        #expect(export.suggestedFileName == "hl.example.com")
    }

    @Test("suggestedFileName counts multiple bookmarks")
    func fileNameMultiple() {
        let export = BookmarkExport(bookmarks: [
            sampleBookmark(name: "A"), sampleBookmark(name: "B"), sampleBookmark(name: "C")
        ])
        #expect(export.suggestedFileName == "3 Bookmarks")
    }

    @Test("suggestedFileName sanitises path separators")
    func fileNameSanitised() {
        let export = BookmarkExport(bookmarks: [sampleBookmark(name: "a/b:c")])
        #expect(export.suggestedFileName == "a-b-c")
    }

    @Test("bookmark(from:) maps name/address/port and leaves login empty")
    func trackerMapping() {
        let server = TrackerServer(address: "hl.example.com", port: 5501, users: 3, name: "Cool BBS", description: "d")
        let mark = BookmarkExport.bookmark(from: server)
        #expect(mark.settings.name == "Cool BBS")
        #expect(mark.settings.address == "hl.example.com")
        #expect(mark.settings.port == 5501)
        #expect(mark.settings.login.isEmpty)
    }

    @Test("singleBookmarkID returns the sole id, else nil")
    func singleSelectionRule() {
        let first = UUID()
        let second = UUID()
        #expect(singleBookmarkID(in: [first]) == first)
        #expect(singleBookmarkID(in: []) == nil)
        #expect(singleBookmarkID(in: [first, second]) == nil)
    }
}
