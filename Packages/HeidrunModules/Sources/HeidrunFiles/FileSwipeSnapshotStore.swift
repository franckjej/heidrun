import CoreGraphics
import HeidrunCore

/// Per-folder page snapshots, scroll offsets and selections for the swipe
/// slide. Snapshots are window-sized bitmaps, so only the `capacity` most
/// recent are kept; offsets and selections are tiny and kept for every folder.
struct FileSwipeSnapshotStore<Snapshot> {
    let capacity: Int
    private var snapshots: [RemotePath: Snapshot] = [:]
    /// Oldest first.
    private var recency: [RemotePath] = []
    private var offsets: [RemotePath: CGPoint] = [:]
    private var selections: [RemotePath: Set<RemoteFile.ID>] = [:]

    init(capacity: Int = 10) {
        self.capacity = capacity
    }

    mutating func store(
        _ snapshot: Snapshot?,
        offset: CGPoint,
        selection: Set<RemoteFile.ID> = [],
        for path: RemotePath
    ) {
        offsets[path] = offset
        selections[path] = selection
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
    func selection(for path: RemotePath) -> Set<RemoteFile.ID> { selections[path] ?? [] }
}
