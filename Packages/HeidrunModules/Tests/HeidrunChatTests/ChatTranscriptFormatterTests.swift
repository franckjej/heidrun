import Testing
@testable import HeidrunChat

@Suite("ChatTranscriptFormatter")
struct ChatTranscriptFormatterTests {
    @Test("formats normal, action, and system lines, one per line")
    func formatsMixedLines() {
        let lines = [
            ChatViewModel.Line(sender: "Erika", body: "hi there"),
            ChatViewModel.Line(sender: nil, body: "Erika waves", isAction: true),
            ChatViewModel.Line(sender: nil, body: "Bob entered", isSystem: true)
        ]
        let transcript = ChatTranscriptFormatter.format(lines)
        #expect(transcript == "Erika: hi there\n* Erika waves\nBob entered")
    }

    @Test("an empty transcript is the empty string")
    func emptyIsEmpty() {
        #expect(ChatTranscriptFormatter.format([]).isEmpty)
    }

    @Test("a normal line without a sender falls back to just the body")
    func senderlessNormalLine() {
        let lines = [ChatViewModel.Line(sender: nil, body: "raw text")]
        #expect(ChatTranscriptFormatter.format(lines) == "raw text")
    }
}
