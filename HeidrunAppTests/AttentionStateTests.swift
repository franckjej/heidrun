import Testing
@testable import Heidrun

@Suite("AttentionState")
@MainActor
struct AttentionStateTests {
    @Test("raise accumulates per feature and totals across features")
    func raiseAccumulates() {
        let attention = AttentionState()
        attention.raise("chat")
        attention.raise("chat")
        attention.raise("news", by: 3)
        #expect(attention.counts["chat"] == 2)
        #expect(attention.counts["news"] == 3)
        #expect(attention.total == 5)
    }

    @Test("set replaces the count; pulse only when it grows")
    func setPulsesOnlyOnGrowth() {
        let attention = AttentionState()
        attention.set("messages", to: 2)
        let afterGrow = attention.pulseToken
        attention.set("messages", to: 1)
        #expect(attention.pulseToken == afterGrow)
        attention.set("messages", to: 4)
        #expect(attention.pulseToken == afterGrow + 1)
        #expect(attention.counts["messages"] == 4)
    }

    @Test("set to zero removes the key")
    func setZeroRemoves() {
        let attention = AttentionState()
        attention.raise("chat")
        attention.set("chat", to: 0)
        #expect(attention.counts["chat"] == nil)
        #expect(attention.total == 0)
    }

    @Test("clear and clearAll drop counts without pulsing")
    func clearDoesNotPulse() {
        let attention = AttentionState()
        attention.raise("chat")
        attention.raise("news")
        let token = attention.pulseToken
        attention.clear("chat")
        #expect(attention.counts["chat"] == nil)
        #expect(attention.total == 1)
        attention.clearAll()
        #expect(attention.total == 0)
        #expect(attention.pulseToken == token)
    }

    @Test("every raise increments the pulse token")
    func raisePulses() {
        let attention = AttentionState()
        #expect(attention.pulseToken == 0)
        attention.raise("chat")
        attention.raise("chat")
        #expect(attention.pulseToken == 2)
    }
}
