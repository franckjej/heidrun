import Foundation
import Testing
@testable import HeidrunMessages
import HeidrunUI

@Suite("MessagesTranscriptProjection")
struct MessagesTranscriptProjectionTests {

    private static let fixed: Date = {
        var components = DateComponents()
        components.year = 2026; components.month = 5; components.day = 23
        components.hour = 12; components.minute = 34; components.second = 56
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    @Test("incoming message uses peer nickname as sender")
    @MainActor
    func incomingSender() {
        let message = MessagesViewModel.Message(
            text: "hello",
            direction: .incoming,
            receivedAt: Self.fixed
        )

        let lines = MessagesTranscriptProjection.lines(
            from: [message],
            ownNickname: "Me",
            peerNickname: "Anna",
            timestampFormatter: Self.utcFormatter
        )

        #expect(lines.count == 1)
        #expect(lines[0].segments.map(\.style) ==
                [.timestamp, .sender, .separator, .body])
        #expect(lines[0].segments[0].text == "12:34:56")
        #expect(lines[0].segments[1].text == "Anna")
        #expect(lines[0].segments[3].text == "hello")
    }

    @Test("outgoing message uses own nickname as sender")
    @MainActor
    func outgoingSender() {
        let message = MessagesViewModel.Message(
            text: "reply",
            direction: .outgoing,
            receivedAt: Self.fixed
        )

        let lines = MessagesTranscriptProjection.lines(
            from: [message],
            ownNickname: "Me",
            peerNickname: "Anna",
            timestampFormatter: Self.utcFormatter
        )

        #expect(lines[0].segments[1].text == "Me")
        #expect(lines[0].segments[3].text == "reply")
    }

    @Test("line id is preserved as the message's UUID string")
    @MainActor
    func idPreserved() {
        let message = MessagesViewModel.Message(
            text: "hi", direction: .incoming, receivedAt: Self.fixed
        )

        let lines = MessagesTranscriptProjection.lines(
            from: [message],
            ownNickname: "Me",
            peerNickname: "Anna",
            timestampFormatter: Self.utcFormatter
        )

        #expect(lines[0].id == message.id.uuidString)
    }
}
