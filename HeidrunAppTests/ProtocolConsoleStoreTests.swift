import Testing
@testable import Heidrun

@MainActor
@Suite("ProtocolConsoleStore reply correlation")
struct ProtocolConsoleStoreTests {
    /// Two simultaneous connections each run their own task counter from 1,
    /// so they routinely reuse the same task number (the recurring "both
    /// ping on task 96" case). The console must correlate each reply back to
    /// its OWN connection's request — keying by task number alone let the
    /// first reply consume the slot and rendered the second as `???`.
    @Test("two connections reusing the same task number both correlate their replies")
    func crossConnectionTaskCollisionLabelsBothReplies() {
        let store = ProtocolConsoleStore()

        // Both connections send a ping (TX 500) on the SAME task number.
        store.append(server: "alpha", direction: .outbound, classID: 0, transactionID: 500, taskNumber: 96, fields: [])
        store.append(server: "beta", direction: .outbound, classID: 0, transactionID: 500, taskNumber: 96, fields: [])

        // Both servers reply (classID 1, type 0, same task) — beta arrives last.
        store.append(server: "alpha", direction: .inbound, classID: 1, transactionID: 0, taskNumber: 96, fields: [])
        store.append(server: "beta", direction: .inbound, classID: 1, transactionID: 0, taskNumber: 96, fields: [])

        let replies = store.entries.filter { $0.direction == .inbound }
        #expect(replies.count == 2)
        for reply in replies {
            guard case .inboundReply(let replyTo) = reply.kind else {
                Issue.record("\(reply.server) reply should correlate to its ping, got \(reply.kind)")
                continue
            }
            #expect(replyTo == 500, "should resolve back to the ping request (TX 500)")
        }
    }

    /// Guard the existing single-connection behaviour: a reply still matches
    /// the request on its own connection.
    @Test("a reply on the same connection still correlates")
    func sameConnectionStillCorrelates() {
        let store = ProtocolConsoleStore()
        store.append(server: "alpha", direction: .outbound, classID: 0, transactionID: 300, taskNumber: 2, fields: [])
        store.append(server: "alpha", direction: .inbound, classID: 1, transactionID: 0, taskNumber: 2, fields: [])

        let reply = store.entries.last
        guard case .inboundReply(let replyTo) = reply?.kind else {
            Issue.record("expected an inboundReply, got \(String(describing: reply?.kind))")
            return
        }
        #expect(replyTo == 300)
    }
}
