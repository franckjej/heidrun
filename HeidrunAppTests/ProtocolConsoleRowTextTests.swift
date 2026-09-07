import Foundation
import Testing
import HeidrunCore
@testable import Heidrun

@MainActor
@Suite("ProtocolConsoleRowText")
struct ProtocolConsoleRowTextTests {
    private func pingEntry(server: String = "tastybytes.org") -> ProtocolConsoleEntry {
        let store = ProtocolConsoleStore()
        store.append(
            server: server,
            connectionID: "conn",
            direction: .outbound,
            classID: 0,
            transactionID: 500,
            taskNumber: 7,
            fields: [PacketField(key: 101, data: Data("hello".utf8))]
        )
        return store.entries[0]
    }

    @Test("row text carries server, task, TX, name and field summary")
    func rowTextContents() {
        let text = ProtocolConsoleRowText.text(for: pingEntry())
        #expect(text.contains("tastybytes.org"))
        #expect(text.contains("task=7"))
        #expect(text.contains("TX=500"))
        #expect(text.contains("ping"))
        #expect(text.contains("msg=\"hello\""))
    }

    @Test("matches is a case-insensitive substring test; empty query matches all")
    func matching() {
        let entry = pingEntry()
        #expect(ProtocolConsoleRowText.matches(entry, query: ""))
        #expect(ProtocolConsoleRowText.matches(entry, query: "PING"))
        #expect(ProtocolConsoleRowText.matches(entry, query: "tx=500"))
        #expect(!ProtocolConsoleRowText.matches(entry, query: "login"))
    }
}
