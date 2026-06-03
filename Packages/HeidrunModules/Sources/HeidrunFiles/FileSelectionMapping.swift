import Foundation
import HeidrunCore

/// Pure translation between the SwiftUI selection (a set of
/// `RemoteFile.ID`) and the AppKit table's row indexes. Kept free of any
/// view state so the round-trip is unit-testable in isolation — the
/// `NSTableView` coordinator is otherwise awkward to exercise.
enum FileSelectionMapping {
    /// Row positions in `files` whose id is in `selection`. Ids with no
    /// matching row (e.g. a file that vanished on refresh) are dropped.
    static func rowIndexes(for selection: Set<RemoteFile.ID>, in files: [RemoteFile]) -> IndexSet {
        var indexes = IndexSet()
        for (index, file) in files.enumerated() where selection.contains(file.id) {
            indexes.insert(index)
        }
        return indexes
    }

    /// The ids at `rows` within `files`. Out-of-range rows are ignored so
    /// a stale selection notification can't index past the end.
    static func selection(forRows rows: IndexSet, in files: [RemoteFile]) -> Set<RemoteFile.ID> {
        var ids = Set<RemoteFile.ID>()
        for row in rows where row >= 0 && row < files.count {
            ids.insert(files[row].id)
        }
        return ids
    }
}
