import Foundation
import Testing
@testable import Heidrun

@Suite("DockBadgeAggregator")
@MainActor
struct DockBadgeAggregatorTests {
    private final class Sink {
        var badges: [String] = []
        var bounces = 0
    }

    private func makeDefaults(badge: Bool = true, bounce: Bool = true) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "DockBadgeAggregatorTests.\(UUID().uuidString)")!
        defaults.set(badge, forKey: AppStorageKeys.dockBadgeForUnreadMessages)
        defaults.set(bounce, forKey: AppStorageKeys.dockBounceOnPrivateMessage)
        return defaults
    }

    private func makeAggregator(
        states: [AttentionState],
        defaults: UserDefaults,
        isAppActive: Bool
    ) -> (DockBadgeAggregator, Sink) {
        let sink = Sink()
        let aggregator = DockBadgeAggregator(
            attentionStates: { states },
            defaults: defaults,
            setBadge: { sink.badges.append($0) },
            bounce: { sink.bounces += 1 },
            isAppActive: { isAppActive }
        )
        return (aggregator, sink)
    }

    @Test("badge is the sum across connections")
    func sumsAcrossConnections() {
        let first = AttentionState()
        let second = AttentionState()
        first.raise("chat", by: 2)
        second.set("messages", to: 3)
        let (aggregator, sink) = makeAggregator(states: [first, second], defaults: makeDefaults(), isAppActive: true)
        aggregator.refresh()
        #expect(sink.badges.last == "5")
    }

    @Test("zero total clears the badge with an empty string")
    func zeroClears() {
        let (aggregator, sink) = makeAggregator(states: [AttentionState()], defaults: makeDefaults(), isAppActive: true)
        aggregator.refresh()
        #expect(sink.badges.last == "")
    }

    @Test("badge setting off always writes empty")
    func badgeSettingOff() {
        let state = AttentionState()
        state.raise("chat")
        let (aggregator, sink) = makeAggregator(states: [state], defaults: makeDefaults(badge: false), isAppActive: true)
        aggregator.refresh()
        #expect(sink.badges.last == "")
    }

    @Test("bounces once per new pulse, only while the app is inactive")
    func bounceOnPulseWhenInactive() {
        let state = AttentionState()
        let (aggregator, sink) = makeAggregator(states: [state], defaults: makeDefaults(), isAppActive: false)
        aggregator.refresh()
        #expect(sink.bounces == 0)
        state.raise("chat")
        aggregator.refresh()
        aggregator.refresh()
        #expect(sink.bounces == 1)

        let (activeAggregator, activeSink) = makeAggregator(states: [state], defaults: makeDefaults(), isAppActive: true)
        activeAggregator.refresh()
        state.raise("chat")
        activeAggregator.refresh()
        #expect(activeSink.bounces == 0)
    }

    @Test("bounce setting off suppresses the bounce")
    func bounceSettingOff() {
        let state = AttentionState()
        let (aggregator, sink) = makeAggregator(states: [state], defaults: makeDefaults(bounce: false), isAppActive: false)
        aggregator.refresh()
        state.raise("chat")
        aggregator.refresh()
        #expect(sink.bounces == 0)
    }
}
