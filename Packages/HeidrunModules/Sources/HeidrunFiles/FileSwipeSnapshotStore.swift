import CoreGraphics
import HeidrunCore

/// Per-folder page snapshots + scroll offsets for the swipe slide.
/// Snapshots are window-sized bitmaps, so only the `capacity` most recent
/// are kept; offsets are tiny and kept for every folder.
struct FileSwipeSnapshotStore<Snapshot> {
    let capacity: Int
    private var snapshots: [RemotePath: Snapshot] = [:]
    /// Oldest first.
    private var recency: [RemotePath] = []
    private var offsets: [RemotePath: CGPoint] = [:]

    init(capacity: Int = 10) {
        self.capacity = capacity
    }

    mutating func store(_ snapshot: Snapshot?, offset: CGPoint, for path: RemotePath) {
        offsets[path] = offset
        recency.removeAll { $0 == path }
        guard let snapshot else {
            snapshots[path] = nil
            return
        }
        snapshots[path] = snapshot
        recency.append(path)
        while recency.count > capacity {
            snapshots[recency.removeFirst()] = nil
        }
    }

    func snapshot(for path: RemotePath) -> Snapshot? { snapshots[path] }
    func offset(for path: RemotePath) -> CGPoint? { offsets[path] }
}
