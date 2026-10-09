import Testing
import HeidrunUI

@Suite("SnapshotCache")
struct SnapshotCacheTests {
    @Test("keeps only the most recent snapshots")
    func evictsOldest() {
        var cache = SnapshotCache<String, String>(capacity: 2)
        cache.store("a", for: "a")
        cache.store("b", for: "b")
        cache.store("c", for: "c")
        #expect(cache.snapshot(for: "a") == nil)
        #expect(cache.snapshot(for: "b") == "b")
        #expect(cache.snapshot(for: "c") == "c")
    }

    @Test("storing a key again makes it the most recent")
    func restoreRefreshesRecency() {
        var cache = SnapshotCache<String, String>(capacity: 2)
        cache.store("a", for: "a")
        cache.store("b", for: "b")
        cache.store("a2", for: "a")
        cache.store("c", for: "c")
        #expect(cache.snapshot(for: "a") == "a2")
        #expect(cache.snapshot(for: "b") == nil)
    }

    @Test("a nil snapshot drops the old one")
    func nilDrops() {
        var cache = SnapshotCache<String, String>(capacity: 2)
        cache.store("a", for: "a")
        cache.store(nil, for: "a")
        #expect(cache.snapshot(for: "a") == nil)
    }
}
