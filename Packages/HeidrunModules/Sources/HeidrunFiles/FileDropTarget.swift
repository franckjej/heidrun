import AppKit
import HeidrunCore

/// Where an external (Finder) drop lands. Pure so the AppKit coordinator's
/// retargeting stays unit-testable, like `FileSelectionMapping`.
enum FileDropTarget {
    /// The folder row the drop should upload into, or `nil` for the
    /// current folder. Only a drop directly ON a real folder row counts —
    /// not the `..` row, not an unresolved alias, not "between rows".
    static func folder(
        atRow row: Int,
        dropOperation: NSTableView.DropOperation,
        in files: [RemoteFile]
    ) -> RemoteFile? {
        guard dropOperation == .on, row >= 0, row < files.count else { return nil }
        let candidate = files[row]
        guard candidate.isFolder, !candidate.isParentPlaceholder, !candidate.isUnresolvedAlias else {
            return nil
        }
        return candidate
    }
}
