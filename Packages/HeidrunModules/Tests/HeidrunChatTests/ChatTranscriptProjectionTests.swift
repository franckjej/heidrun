import Foundation
import Testing
@testable import HeidrunChat
import HeidrunUI

@Suite("ChatTranscriptProjection")
struct ChatTranscriptProjectionTests {

    /// Fixed reference date so timestamp formatting is deterministic.
    private static let fixed: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 23
        components.hour = 12
        components.minute = 34
        components.second = 56
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @Test("normal line with timestamp ON → [timestamp, sender, separator, body]")
    @MainActor
    func normalWithTimestamp() {
        let chatLine = ChatViewModel.Line(
            sender: "Jens",
            body: "hello",
            isAction: false,
            isSystem: false,
            receivedAt: Self.fixed
        )

        let lines = ChatTranscriptProjection.lines(
            from: [chatLine],
            showTimestamps: true,
            timestampFormatter: Self.utcFormatter
        )

        #expect(lines.count == 1)
        #expect(lines[0].segments.map(\.style) ==
                [.timestamp, .sender, .separator, .body])
        #expect(lines[0].segments[0].text == "12:34:56")
        #expect(lines[0].segments[1].text == "Jens")
        #expect(lines[0].segments[2].text == ": ")
        #expect(lines[0].segments[3].text == "hello")
    }

    @Test("normal line with timestamp OFF → [sender, separator, body]")
    @MainActor
    func normalWithoutTimestamp() {
        let chatLine = ChatViewModel.Line(
            sender: "Jens",
            body: "hello",
            receivedAt: Self.fixed
        )

        let lines = ChatTranscriptProjection.lines(
            from: [chatLine],
            showTimestamps: false,
            timestampFormatter: Self.utcFormatter
        )

        #expect(lines[0].segments.map(\.style) == [.sender, .separator, .body])
    }

    @Test("action line with timestamp ON → [timestamp, action(\"* body\")]")
    @MainActor
    func actionWithTimestamp() {
        let chatLine = ChatViewModel.Line(
            sender: nil,
            body: "waves",
            isAction: true,
            isSystem: false,
            receivedAt: Self.fixed
        )

        let lines = ChatTranscriptProjection.lines(
            from: [chatLine],
            showTimestamps: true,
            timestampFormatter: Self.utcFormatter
        )

        #expect(lines[0].segments.map(\.style) == [.timestamp, .action])
        #expect(lines[0].segments[1].text == "* waves")
    }

    @Test("action line with timestamp OFF → [action(\"* body\")]")
    @MainActor
    func actionWithoutTimestamp() {
        let chatLine = ChatViewModel.Line(
            sender: nil,
            body: "waves",
            isAction: true,
            isSystem: false,
            receivedAt: Self.fixed
        )

        let lines = ChatTranscriptProjection.lines(
            from: [chatLine],
            showTimestamps: false,
            timestampFormatter: Self.utcFormatter
        )

        #expect(lines[0].segments.map(\.style) == [.action])
        #expect(lines[0].segments[0].text == "* waves")
    }

    @Test("system line always has timestamp regardless of toggle")
    @MainActor
    func systemAlwaysTimestamped() {
        let chatLine = ChatViewModel.Line(
            sender: nil,
            body: "Bob joined",
            isAction: false,
            isSystem: true,
            receivedAt: Self.fixed
        )

        let withFlag = ChatTranscriptProjection.lines(
            from: [chatLine],
            showTimestamps: false,
            timestampFormatter: Self.utcFormatter
        )
        let withoutFlag = ChatTranscriptProjection.lines(
            from: [chatLine],
            showTimestamps: true,
            timestampFormatter: Self.utcFormatter
        )

        #expect(withFlag[0].segments.map(\.style)    == [.timestamp, .system])
        #expect(withoutFlag[0].segments.map(\.style) == [.timestamp, .system])
    }

    @Test("line id is preserved as the chat line's UUID string")
    @MainActor
    func idPreserved() {
        let id = UUID()
        let chatLine = ChatViewModel.Line(
            sender: "Jens",
            body: "hi",
            receivedAt: Self.fixed,
            id: id
        )

        let lines = ChatTranscriptProjection.lines(
            from: [chatLine],
            showTimestamps: false,
            timestampFormatter: Self.utcFormatter
        )

        #expect(lines[0].id == id.uuidString)
    }
}
