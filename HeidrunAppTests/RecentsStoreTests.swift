import Foundation
import Testing
@testable import Heidrun
import HeidrunCore

@MainActor
@Suite("RecentsStore")
struct RecentsStoreTests {
    private func makeStore(suiteName: String = "RecentsStoreTests.\(UUID().uuidString)") -> RecentsStore {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return RecentsStore(defaults: defaults)
    }

    @Test("empty by default")
    func startsEmpty() {
        let store = makeStore()
        #expect(store.entries.isEmpty)
    }

    @Test("record adds entries newest-first")
    func recordOrdersNewestFirst() {
        let store = makeStore()
        store.record(ConnectionSettings(name: "A", address: "a"))
        store.record(ConnectionSettings(name: "B", address: "b"))
        #expect(store.entries.map(\.name) == ["B", "A"])
    }

    @Test("identical entry de-duplicates and bubbles to top")
    func recordDedupes() {
        let store = makeStore()
        store.record(ConnectionSettings(name: "A", address: "a"))
        store.record(ConnectionSettings(name: "B", address: "b"))
        store.record(ConnectionSettings(name: "A", address: "a"))
        #expect(store.entries.map(\.name) == ["A", "B"])
    }

    @Test("dedup key is name + address + port + login")
    func dedupKey() {
        let store = makeStore()
        store.record(ConnectionSettings(name: "A", address: "a", port: 5500, login: "alice"))
        store.record(ConnectionSettings(name: "A", address: "a", port: 5500, login: "bob"))
        #expect(store.entries.count == 2)
    }

    @Test("bounded to 10 entries (oldest evicted)")
    func boundedToTen() {
        let store = makeStore()
        for i in 0..<12 {
            store.record(ConnectionSettings(name: "S\(i)", address: "a\(i)"))
        }
        #expect(store.entries.count == 10)
        #expect(store.entries.first?.name == "S11")
        #expect(store.entries.last?.name == "S2")
    }

    @Test("persisted JSON contains no 'password' key")
    func noPasswordInJSON() {
        let suite = "RecentsStoreTests.password.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = RecentsStore(defaults: defaults)
        store.record(ConnectionSettings(name: "X", address: "x", login: "user"))

        let raw = defaults.data(forKey: RecentsStore.storageKey)!
        let asString = String(bytes: raw, encoding: .utf8) ?? ""
        #expect(!asString.lowercased().contains("password"))
    }

    @Test("clear empties the store")
    func clearEmpties() {
        let store = makeStore()
        store.record(ConnectionSettings(name: "A", address: "a"))
        store.clear()
        #expect(store.entries.isEmpty)
    }

    @Test("entries survive instance reload from same defaults")
    func entriesRoundTripThroughDefaults() {
        let suite = "RecentsStoreTests.roundtrip.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let storeA = RecentsStore(defaults: defaults)
        storeA.record(ConnectionSettings(name: "A", address: "a"))

        let storeB = RecentsStore(defaults: defaults)
        #expect(storeB.entries.map(\.name) == ["A"])
    }
}
