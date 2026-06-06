import Testing
@testable import HeidrunUI

@Suite("InputHistory")
struct InputHistoryTests {
    @Test("record skips empty and consecutive duplicates")
    func recordSkipsEmptyAndDuplicates() {
        var history = InputHistory()
        history.record("hello")
        history.record("   ")        // whitespace-only → skipped
        history.record("hello")      // consecutive duplicate → skipped
        history.record("world")
        history.record("world")      // consecutive duplicate → skipped
        #expect(history.recent == ["world", "hello"])
    }

    @Test("recent is newest-first")
    func recentNewestFirst() {
        var history = InputHistory()
        history.record("one")
        history.record("two")
        history.record("three")
        #expect(history.recent == ["three", "two", "one"])
    }

    @Test("capacity drops the oldest entries")
    func capacityDropsOldest() {
        var history = InputHistory(capacity: 3)
        for message in ["a", "b", "c", "d", "e"] { history.record(message) }
        #expect(history.recent == ["e", "d", "c"])
    }

    @Test("up/down recall cycles through history and restores the live draft")
    func recallCycle() {
        var history = InputHistory()
        history.record("first")
        history.record("second")

        // Start from an in-progress draft "typing…".
        #expect(history.recallPrevious(currentDraft: "typing…") == "second")  // newest
        #expect(history.recallPrevious(currentDraft: "typing…") == "first")   // older
        #expect(history.recallPrevious(currentDraft: "typing…") == nil)       // at oldest → no change
        #expect(history.recallNext() == "second")                             // newer
        #expect(history.recallNext() == "typing…")                           // past newest → restored draft
        #expect(history.recallNext() == nil)                                  // not navigating
    }

    @Test("recallNext returns nil when not navigating")
    func recallNextWithoutNavigation() {
        var history = InputHistory()
        history.record("x")
        #expect(history.recallNext() == nil)
    }

    @Test("recallPrevious on empty history returns nil")
    func recallPreviousEmpty() {
        var history = InputHistory()
        #expect(history.recallPrevious(currentDraft: "anything") == nil)
    }

    @Test("recording resets navigation")
    func recordResetsNavigation() {
        var history = InputHistory()
        history.record("a")
        history.record("b")
        _ = history.recallPrevious(currentDraft: "draft")  // now navigating
        history.record("c")                                // resets nav
        // recallNext should report not-navigating after the reset.
        #expect(history.recallNext() == nil)
    }
}
