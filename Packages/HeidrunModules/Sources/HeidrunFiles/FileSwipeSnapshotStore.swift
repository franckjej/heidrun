import CoreGraphics
import HeidrunCore
import HeidrunUI

/// Per-folder page snapshots, scroll offsets and selections for the swipe
/// slide. Only the most recent snapshots are kept; offsets and selections
/// are tiny and kept for every folder.
struct FileSwipeSnapshotStore<Snapshot> {
    private var snapshots: SnapshotCache<RemotePath, Snapshot>
    private var offsets: [RemotePath: CGPoint] = [:]
    private var selections: [RemotePath: Set<RemoteFile.ID>] = [:]

    init(capacity: Int = 10) {
        snapshots = SnapshotCache(capacity: capacity)
    }

    mutating func store(
        _ snapshot: Snapshot?,
        offset: CGPoint,
        selection: Set<RemoteFile.ID> = [],
        for path: RemotePath
    ) {
        offsets[path] = offset
        selections[path] = selection
        snapshots.store(snapshot, for: path)
    }

    func snapshot(for path: RemotePath) -> Snapshot? { snapshots.snapshot(for: path) }
    func offset(for path: RemotePath) -> CGPoint? { offsets[path] }
    func selection(for path: RemotePath) -> Set<RemoteFile.ID> { selections[path] ?? [] }
}
