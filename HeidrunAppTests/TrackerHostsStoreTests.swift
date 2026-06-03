import Foundation
import Testing
@testable import Heidrun

@MainActor
@Suite("TrackerHostsStore")
struct TrackerHostsStoreTests {
    private func makeStore(
        suiteName: String = "TrackerHostsStoreTests.\(UUID().uuidString)"
    ) -> (TrackerHostsStore, UserDefaults) {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (TrackerHostsStore(defaults: defaults), defaults)
    }

    @Test("first read seeds default hltracker.com")
    func firstReadSeedsDefault() throws {
        let (store, _) = makeStore()
        #expect(store.hosts.count == 1)
        let only = try #require(store.hosts.first)
        #expect(only.host == "hltracker.com")
        #expect(only.port == 5498)
        #expect(only.enabled == true)
    }

    @Test("default seed only happens once; clearing leaves an empty list")
    func clearLeavesEmpty() {
        let (store, _) = makeStore()
        store.removeAll()
        #expect(store.hosts.isEmpty)
        // Re-instantiating against the same defaults must NOT re-seed
        // because we've explicitly written an empty list.
        let reopened = TrackerHostsStore(defaults: store.defaultsForTesting)
        #expect(reopened.hosts.isEmpty)
    }

    @Test("append persists across re-instantiation")
    func appendPersists() {
        let (store, defaults) = makeStore()
        store.append(TrackerHost(name: "preter", host: "tracker.preterhuman.net"))
        let reopened = TrackerHostsStore(defaults: defaults)
        #expect(reopened.hosts.map(\.host) == ["hltracker.com", "tracker.preterhuman.net"])
    }

    @Test("update by id mutates the row in place")
    func updateMutatesInPlace() throws {
        let (store, _) = makeStore()
        let original = try #require(store.hosts.first)
        var edited = original
        edited.name = "renamed"
        edited.enabled = false
        store.update(edited)
        #expect(store.hosts.first?.name == "renamed")
        #expect(store.hosts.first?.enabled == false)
    }

    @Test("remove by id drops the row")
    func removeByID() throws {
        let (store, _) = makeStore()
        store.append(TrackerHost(name: "extra", host: "extra.example.com"))
        let target = try #require(store.hosts.last)
        store.remove(target.id)
        #expect(store.hosts.contains(where: { $0.id == target.id }) == false)
        #expect(store.hosts.count == 1)
    }

    @Test("malformed JSON in defaults falls back to the seed")
    func malformedFallsBackToSeed() {
        let suite = "TrackerHostsStoreTests.malformed.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(Data([0xFF, 0xFE, 0xFD]), forKey: AppStorageKeys.trackerHosts)
        let store = TrackerHostsStore(defaults: defaults)
        #expect(store.hosts.count == 1)
        #expect(store.hosts.first?.host == "hltracker.com")
    }
}
