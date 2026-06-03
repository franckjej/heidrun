import Foundation
import Testing
import HeidrunCore
@testable import HeidrunBookmarks

@Suite("BookmarkCSVWriter")
struct BookmarkCSVWriterTests {

    private func makeBookmark(name: String, address: String, port: UInt16 = 5500, login: String = "bob", nickname: String = "Bob", icon: UInt16 = 410) -> Bookmark {
        Bookmark(settings: ConnectionSettings(
            name: name,
            address: address,
            port: port,
            nickname: nickname,
            login: login,
            icon: icon
        ))
    }

    @Test("output starts with the header row")
    func headerRow() {
        let output = BookmarkCSVWriter.write([])
        #expect(output == "Name,Address,Port,Login,Nickname,Icon\n")
    }

    @Test("plain bookmarks render without quoting")
    func plainBookmarksRender() {
        let marks = [makeBookmark(name: "Carpe", address: "carpe.example.com")]
        let output = BookmarkCSVWriter.write(marks)
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 3)        // header + 1 entry + trailing empty after final \n
        #expect(lines[1] == "Carpe,carpe.example.com,5500,bob,Bob,410")
    }

    @Test("fields containing commas are quoted")
    func quotesEmbeddedCommas() {
        let marks = [makeBookmark(name: "Carpe, Diem", address: "carpe.example.com")]
        let output = BookmarkCSVWriter.write(marks)
        #expect(output.contains("\"Carpe, Diem\","))
    }

    @Test("embedded double-quotes are doubled and the field quoted")
    func doublesEmbeddedQuotes() {
        let marks = [makeBookmark(name: "Tom's \"BBS\"", address: "tom.example.com")]
        let output = BookmarkCSVWriter.write(marks)
        // The inner " becomes "" inside the quoted field.
        #expect(output.contains("\"Tom's \"\"BBS\"\"\","))
    }

    @Test("embedded newlines are preserved inside a quoted field")
    func preservesEmbeddedNewlines() {
        let marks = [makeBookmark(name: "Line1\nLine2", address: "x.example.com")]
        let output = BookmarkCSVWriter.write(marks)
        #expect(output.contains("\"Line1\nLine2\","))
    }

    @Test("embedded carriage return is preserved inside a quoted field")
    func preservesEmbeddedCarriageReturn() {
        let marks = [makeBookmark(name: "Carpe\rDiem", address: "carpe.example.com")]
        let output = BookmarkCSVWriter.write(marks)
        #expect(output.contains("\"Carpe\rDiem\","))
    }

    @Test("multiple bookmarks join with the row separator")
    func multipleBookmarksJoinWithRowSeparator() {
        let marks = [
            makeBookmark(name: "Carpe", address: "carpe.example.com"),
            makeBookmark(name: "Tom", address: "tom.example.com")
        ]
        let output = BookmarkCSVWriter.write(marks)
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 4)        // header + 2 entries + trailing empty after final \n
        #expect(lines[1] == "Carpe,carpe.example.com,5500,bob,Bob,410")
        #expect(lines[2] == "Tom,tom.example.com,5500,bob,Bob,410")
    }

    @Test("empty string fields are not quoted")
    func emptyFieldsAreNotQuoted() {
        let marks = [makeBookmark(name: "Guest", address: "guest.example.com", login: "", nickname: "")]
        let output = BookmarkCSVWriter.write(marks)
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[1] == "Guest,guest.example.com,5500,,,410")
    }
}
