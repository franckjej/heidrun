/// The `capacity` most recently stored page snapshots by key. Snapshots
/// are window-sized bitmaps, so older ones are dropped.
public struct SnapshotCache<Key: Hashable, Snapshot> {
    public let capacity: Int
    private var snapshots: [Key: Snapshot] = [:]
    /// Oldest first.
    private var recency: [Key] = []

    public init(capacity: Int = 10) {
        self.capacity = capacity
    }

    /// Stores `snapshot` as the most recent; nil drops the old one.
    public mutating func store(_ snapshot: Snapshot?, for key: Key) {
        recency.removeAll { $0 == key }
        guard let snapshot else {
            snapshots[key] = nil
            return
        }
        snapshots[key] = snapshot
        recency.append(key)
        while recency.count > capacity {
            snapshots[recency.removeFirst()] = nil
        }
    }

    public func snapshot(for key: Key) -> Snapshot? { snapshots[key] }
}
