import Foundation
import Testing
import AppKit
@testable import Heidrun

/// Coverage for the unread-count logic that drives the Dock icon badge.
/// The visible side-effect (the `UNUserNotificationCenter.setBadgeCount`
/// call) isn't asserted here — the counter's mutable state is what
/// matters for whether the right number gets pushed.
///
/// The "is the app frontmost?" check is injected so each test can pin
/// the foreground/background state regardless of what the test runner
/// process reports for `NSApp.isActive`.
@MainActor
@Suite("BadgeCounter")
struct BadgeCounterTests {
    private static func backgroundedCounter() -> BadgeCounter {
        BadgeCounter(isAppActive: { false })
    }

    private static func frontmostCounter() -> BadgeCounter {
        BadgeCounter(isAppActive: { true })
    }

    @Test("starts at zero")
    func startsAtZero() {
        let counter = Self.backgroundedCounter()
        #expect(counter.unreadCount == 0)
    }

    @Test("private message increments while the app is in the background")
    func incrementsPrivateMessage() {
        let counter = Self.backgroundedCounter()
        counter.increment(for: .privateMessage)
        counter.increment(for: .privateMessage)
        #expect(counter.unreadCount == 2)
    }

    @Test("chat invite increments while the app is in the background")
    func incrementsChatInvite() {
        let counter = Self.backgroundedCounter()
        counter.increment(for: .chatInvite)
        #expect(counter.unreadCount == 1)
    }

    @Test("frontmost app suppresses increments")
    func frontmostSuppressesIncrements() {
        let counter = Self.frontmostCounter()
        counter.increment(for: .privateMessage)
        counter.increment(for: .chatInvite)
        #expect(counter.unreadCount == 0)
    }

    @Test("non-badge kinds never increment")
    func ignoresNonBadgeKinds() {
        let counter = Self.backgroundedCounter()
        counter.increment(for: .connected)
        counter.increment(for: .disconnected)
        counter.increment(for: .transferFinished)
        counter.increment(for: .newsPosted)
        counter.increment(for: .broadcast)
        #expect(counter.unreadCount == 0)
    }

    @Test("reset clears the count")
    func resetClears() {
        let counter = Self.backgroundedCounter()
        counter.increment(for: .privateMessage)
        counter.increment(for: .chatInvite)
        counter.reset()
        #expect(counter.unreadCount == 0)
    }

    @Test("reset is a no-op when already zero")
    func resetWhenZero() {
        let counter = Self.backgroundedCounter()
        counter.reset()
        #expect(counter.unreadCount == 0)
    }
}
