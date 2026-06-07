import Testing
@testable import Heidrun

@MainActor
@Suite("ProtocolConsoleStore reply correlation")
struct ProtocolConsoleStoreTests {
    /// Append helper — all entries share one display server so the tests
    /// exercise the same-server case; `connection` is the per-connection
    /// correlation token.
    private func record(
        _ store: ProtocolConsoleStore,
        connection: String,
        direction: ProtocolConsoleEntry.Direction,
        classID: UInt16,
        transactionID: UInt16,
        taskNumber: UInt32
    ) {
        store.append(
            server: "tastybytes.org",
            connectionID: connection,
            direction: direction,
            classID: classID,
            transactionID: transactionID,
            taskNumber: taskNumber,
            fields: []
        )
    }

    /// Two connections — even to the SAME server — each run their own task
    /// counter from 1, so they reuse the same task number. The console must
    /// correlate each reply to its OWN connection by the per-connection
    /// token, not the server name. Keying by server (or task alone) let one
    /// reply consume the slot and rendered the other as `???`.
    @Test("two connections to the same server both correlate their replies")
    func sameServerTwoConnectionsBothCorrelate() {
        let store = ProtocolConsoleStore()

        // Both connections (distinct tokens) send a ping (TX 500) on task 96.
        record(store, connection: "conn-A", direction: .outbound, classID: 0, transactionID: 500, taskNumber: 96)
        record(store, connection: "conn-B", direction: .outbound, classID: 0, transactionID: 500, taskNumber: 96)

        // Both reply (classID 1, type 0, same task) — conn-B arrives last.
        record(store, connection: "conn-A", direction: .inbound, classID: 1, transactionID: 0, taskNumber: 96)
        record(store, connection: "conn-B", direction: .inbound, classID: 1, transactionID: 0, taskNumber: 96)

        let replies = store.entries.filter { $0.direction == .inbound }
        #expect(replies.count == 2)
        for reply in replies {
            guard case .inboundReply(let replyTo) = reply.kind else {
                Issue.record("a same-server reply should correlate to its ping, got \(reply.kind)")
                continue
            }
            #expect(replyTo == 500, "should resolve back to the ping request (TX 500)")
        }
    }

    /// Guard single-connection behaviour: a reply still matches the request
    /// on its own connection.
    @Test("a reply on the same connection still correlates")
    func sameConnectionStillCorrelates() {
        let store = ProtocolConsoleStore()
        record(store, connection: "conn-A", direction: .outbound, classID: 0, transactionID: 300, taskNumber: 2)
        record(store, connection: "conn-A", direction: .inbound, classID: 1, transactionID: 0, taskNumber: 2)

        let reply = store.entries.last
        guard case .inboundReply(let replyTo) = reply?.kind else {
            Issue.record("expected an inboundReply, got \(String(describing: reply?.kind))")
            return
        }
        #expect(replyTo == 300)
    }
}
