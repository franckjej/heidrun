import Foundation
import Testing
@testable import Heidrun
import HeidrunCore
import HeidrunBookmarks

@MainActor
@Suite("AutoReconnectCoordinator.shouldAutoReconnect")
struct AutoReconnectCoordinatorShouldTests {

    private func sampleSettings() -> ConnectionSettings {
        ConnectionSettings(
            name: "Sample",
            address: "sample.example.com",
            port: 5500,
            nickname: "tester",
            login: ""
        )
    }

    private func makeCoordinator(
        globalEnabled: Bool,
        maxAttempts: Int = 3,
        bookmark: Bookmark? = nil
    ) -> AutoReconnectCoordinator {
        AutoReconnectCoordinator(
            settingsProvider: {
                AutoReconnectGlobalSettings(
                    isEnabled: globalEnabled,
                    maxAttempts: maxAttempts,
                    delaySeconds: 0
                )
            },
            bookmarkLookup: { _ in bookmark },
            sleep: { _ in }
        )
    }

    @Test("global off + no matching bookmark → false")
    func globalOffAdHoc() {
        let coordinator = makeCoordinator(globalEnabled: false, bookmark: nil)
        #expect(coordinator.shouldAutoReconnect(reason: "lost", settings: sampleSettings()) == false)
    }

    @Test("global off + bookmark .inherit → false")
    func globalOffInherit() {
        let mark = Bookmark(settings: sampleSettings(), autoReconnect: .inherit)
        let coordinator = makeCoordinator(globalEnabled: false, bookmark: mark)
        #expect(coordinator.shouldAutoReconnect(reason: "lost", settings: sampleSettings()) == false)
    }

    @Test("global off + bookmark .alwaysOn → true")
    func globalOffAlwaysOn() {
        let mark = Bookmark(settings: sampleSettings(), autoReconnect: .alwaysOn)
        let coordinator = makeCoordinator(globalEnabled: false, bookmark: mark)
        #expect(coordinator.shouldAutoReconnect(reason: "lost", settings: sampleSettings()) == true)
    }

    @Test("global on + bookmark .alwaysOff → false")
    func globalOnAlwaysOff() {
        let mark = Bookmark(settings: sampleSettings(), autoReconnect: .alwaysOff)
        let coordinator = makeCoordinator(globalEnabled: true, bookmark: mark)
        #expect(coordinator.shouldAutoReconnect(reason: "lost", settings: sampleSettings()) == false)
    }

    @Test("global on + bookmark .inherit → true")
    func globalOnInherit() {
        let mark = Bookmark(settings: sampleSettings(), autoReconnect: .inherit)
        let coordinator = makeCoordinator(globalEnabled: true, bookmark: mark)
        #expect(coordinator.shouldAutoReconnect(reason: "lost", settings: sampleSettings()) == true)
    }

    @Test("global on + no matching bookmark (ad-hoc) → true")
    func globalOnAdHoc() {
        let coordinator = makeCoordinator(globalEnabled: true, bookmark: nil)
        #expect(coordinator.shouldAutoReconnect(reason: "lost", settings: sampleSettings()) == true)
    }

    @Test("reason containing 'server error' (kick / protocol error) → false")
    func reasonServerErrorFiltered() {
        let coordinator = makeCoordinator(globalEnabled: true, bookmark: nil)
        #expect(coordinator.shouldAutoReconnect(reason: "server error 5: kicked by admin", settings: sampleSettings()) == false)
    }

    @Test("nil reason still allows retry when otherwise enabled")
    func nilReasonStillAllowsRetry() {
        let coordinator = makeCoordinator(globalEnabled: true, bookmark: nil)
        #expect(coordinator.shouldAutoReconnect(reason: nil, settings: sampleSettings()) == true)
    }
}

@MainActor
@Suite("AutoReconnectCoordinator.scheduleRetry")
struct AutoReconnectCoordinatorScheduleTests {

    private func sampleSettings() -> ConnectionSettings {
        ConnectionSettings(
            name: "Sample",
            address: "sample.example.com",
            port: 5500,
            nickname: "tester",
            login: ""
        )
    }

    @Test("scheduleRetry increments attempt and runs the closure")
    func scheduleRunsClosure() async {
        let calls = Mutex(0)
        let coordinator = AutoReconnectCoordinator(
            settingsProvider: {
                AutoReconnectGlobalSettings(isEnabled: true, maxAttempts: 3, delaySeconds: 0)
            },
            bookmarkLookup: { _ in nil },
            sleep: { _ in }
        )
        coordinator.scheduleRetry { calls.set(calls.get() + 1) }
        // Wait for the scheduled Task's closure to land (condition, not a
        // fixed guess — see `poll`).
        await poll { calls.get() == 1 }
        #expect(coordinator.attempt == 1)
        #expect(coordinator.maxAttempts == 3)
        #expect(calls.get() == 1)
    }

    @Test("scheduleRetry passes the configured delay to the sleep closure")
    func scheduleUsesConfiguredDelay() async {
        let observedDelay = Mutex<Duration?>(nil)
        let coordinator = AutoReconnectCoordinator(
            settingsProvider: {
                AutoReconnectGlobalSettings(isEnabled: true, maxAttempts: 3, delaySeconds: 7)
            },
            bookmarkLookup: { _ in nil },
            sleep: { duration in observedDelay.set(duration) }
        )
        coordinator.scheduleRetry { }
        await poll { observedDelay.get() != nil }
        #expect(observedDelay.get() == .seconds(7))
    }

    @Test("scheduleRetry past maxAttempts is a no-op")
    func scheduleStopsAtCap() async {
        let calls = Mutex(0)
        let coordinator = AutoReconnectCoordinator(
            settingsProvider: {
                AutoReconnectGlobalSettings(isEnabled: true, maxAttempts: 2, delaySeconds: 0)
            },
            bookmarkLookup: { _ in nil },
            sleep: { _ in }
        )
        coordinator.scheduleRetry { calls.set(calls.get() + 1) }
        coordinator.scheduleRetry { calls.set(calls.get() + 1) }
        coordinator.scheduleRetry { calls.set(calls.get() + 1) }  // capped
        // Exactly two attempts pass the cap; wait for both closures to run.
        await poll { calls.get() == 2 }
        #expect(coordinator.attempt == 2)
        #expect(calls.get() == 2)
    }

    @Test("reset clears the counter")
    func resetClears() async {
        let coordinator = AutoReconnectCoordinator(
            settingsProvider: {
                AutoReconnectGlobalSettings(isEnabled: true, maxAttempts: 3, delaySeconds: 0)
            },
            bookmarkLookup: { _ in nil },
            sleep: { _ in }
        )
        coordinator.scheduleRetry { }
        try? await Task.sleep(for: .milliseconds(20))
        #expect(coordinator.attempt == 1)
        coordinator.reset()
        #expect(coordinator.attempt == 0)
    }

    @Test("cancel prevents the pending closure from running")
    func cancelPreventsClosure() async {
        let calls = Mutex(0)
        let coordinator = AutoReconnectCoordinator(
            settingsProvider: {
                AutoReconnectGlobalSettings(isEnabled: true, maxAttempts: 3, delaySeconds: 0)
            },
            bookmarkLookup: { _ in nil },
            sleep: { _ in
                // Long-enough delay that cancel() lands first.
                try? await Task.sleep(for: .milliseconds(50))
            }
        )
        coordinator.scheduleRetry { calls.set(calls.get() + 1) }
        coordinator.cancel()
        try? await Task.sleep(for: .milliseconds(80))
        #expect(calls.get() == 0)
        // cancel() does NOT reset the counter — attempt was already
        // incremented when scheduleRetry started.
        #expect(coordinator.attempt == 1)
    }
}
