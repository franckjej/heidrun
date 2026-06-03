import Foundation
import Testing
@testable import Heidrun
import HeidrunCore

/// Coverage for the small persistence + queue pair that drives
/// "reopen previous connections on launch". Both pieces are pure
/// value-shuffling — no `NWConnection`, no Keychain — so the tests
/// pin the round trip and the FIFO ordering without standing up a
/// full app.
@Suite("SessionRestorationStore")
struct SessionRestorationStoreTests {
    private func makeIsolatedDefaults() -> UserDefaults {
        // A per-test suite name keeps the test run isolated from the
        // user's real preferences plist.
        let suiteName = "Heidrun.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func sampleSettings(name: String) -> ConnectionSettings {
        ConnectionSettings(
            name: name,
            address: "\(name.lowercased()).example.com",
            port: 5500,
            nickname: "tester",
            login: "guest"
        )
    }

    @Test("save / load round-trips a non-empty array")
    func roundTripsSettings() {
        let defaults = makeIsolatedDefaults()
        let store = SessionRestorationStore(defaults: defaults, storageKey: "Heidrun.test")
        let original = [sampleSettings(name: "Alpha"), sampleSettings(name: "Beta")]

        store.save(original)
        let loaded = store.load()

        #expect(loaded == original)
    }

    @Test("save of an empty array removes the key (load returns [])")
    func emptySaveClears() {
        let defaults = makeIsolatedDefaults()
        let store = SessionRestorationStore(defaults: defaults, storageKey: "Heidrun.test")
        store.save([sampleSettings(name: "Alpha")])
        store.save([])

        #expect(defaults.data(forKey: "Heidrun.test") == nil)
        #expect(store.load().isEmpty)
    }

    @Test("clear() drops the snapshot")
    func clearRemovesSnapshot() {
        let defaults = makeIsolatedDefaults()
        let store = SessionRestorationStore(defaults: defaults, storageKey: "Heidrun.test")
        store.save([sampleSettings(name: "Alpha")])
        store.clear()

        #expect(store.load().isEmpty)
    }

    @Test("load on a fresh defaults returns an empty array")
    func loadEmptyIsClean() {
        let store = SessionRestorationStore(
            defaults: makeIsolatedDefaults(),
            storageKey: "Heidrun.test"
        )
        #expect(store.load().isEmpty)
    }
}

@MainActor
@Suite("SessionRestorationQueue")
struct SessionRestorationQueueTests {
    private func sampleSettings(name: String) -> ConnectionSettings {
        ConnectionSettings(
            name: name,
            address: "\(name.lowercased()).example.com",
            port: 5500,
            nickname: "tester",
            login: "guest"
        )
    }

    @Test("populate then dequeue returns entries FIFO")
    func dequeueFIFO() {
        let queue = SessionRestorationQueue.shared
        queue.populate([
            sampleSettings(name: "Alpha"),
            sampleSettings(name: "Beta"),
            sampleSettings(name: "Gamma")
        ])

        #expect(queue.count == 3)
        #expect(queue.dequeue()?.name == "Alpha")
        #expect(queue.dequeue()?.name == "Beta")
        #expect(queue.dequeue()?.name == "Gamma")
        #expect(queue.dequeue() == nil)
        #expect(queue.isEmpty)
    }

    @Test("populate replaces any previously-pending entries")
    func populateReplaces() {
        let queue = SessionRestorationQueue.shared
        queue.populate([sampleSettings(name: "Old")])
        queue.populate([sampleSettings(name: "New")])

        #expect(queue.dequeue()?.name == "New")
        #expect(queue.isEmpty)
    }
}
