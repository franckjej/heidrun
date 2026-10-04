import Foundation
import Testing
@testable import HeidrunFiles
import HeidrunCore

@Suite("FileSwipeSnapshotStore")
struct FileSwipeSnapshotStoreTests {
    @Test("keeps only the most recent snapshots but every scroll offset")
    func evictsOldestSnapshot() {
        var store = FileSwipeSnapshotStore<String>(capacity: 2)
        store.store("a", offset: CGPoint(x: 0, y: 10), for: ["a"])
        store.store("b", offset: CGPoint(x: 0, y: 20), for: ["b"])
        store.store("c", offset: CGPoint(x: 0, y: 30), for: ["c"])
        #expect(store.snapshot(for: ["a"]) == nil)
        #expect(store.snapshot(for: ["b"]) == "b")
        #expect(store.snapshot(for: ["c"]) == "c")
        #expect(store.offset(for: ["a"]) == CGPoint(x: 0, y: 10))
    }

    @Test("storing a folder again makes it the most recent")
    func restoreRefreshesRecency() {
        var store = FileSwipeSnapshotStore<String>(capacity: 2)
        store.store("a", offset: .zero, for: ["a"])
        store.store("b", offset: .zero, for: ["b"])
        store.store("a2", offset: .zero, for: ["a"])
        store.store("c", offset: .zero, for: ["c"])
        #expect(store.snapshot(for: ["a"]) == "a2")
        #expect(store.snapshot(for: ["b"]) == nil)
    }

    @Test("a nil snapshot drops the old one but keeps the offset")
    func nilSnapshotDropsImage() {
        var store = FileSwipeSnapshotStore<String>(capacity: 2)
        store.store("a", offset: .zero, for: ["a"])
        store.store(nil, offset: CGPoint(x: 0, y: 5), for: ["a"])
        #expect(store.snapshot(for: ["a"]) == nil)
        #expect(store.offset(for: ["a"]) == CGPoint(x: 0, y: 5))
    }

    @Test("remembers each folder's selection, empty when unknown")
    func keepsSelection() {
        var store = FileSwipeSnapshotStore<String>(capacity: 1)
        store.store("a", offset: .zero, selection: ["x", "y"], for: ["a"])
        store.store("b", offset: .zero, for: ["b"])
        #expect(store.selection(for: ["a"]) == ["x", "y"])
        #expect(store.selection(for: ["b"]).isEmpty)
        #expect(store.selection(for: ["c"]).isEmpty)
    }
}
