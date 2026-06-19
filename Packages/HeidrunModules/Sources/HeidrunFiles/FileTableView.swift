import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HeidrunCore
import HeidrunUI
import CommonTools

private extension NSPasteboard.PasteboardType {
    /// Internal-only marker identifying a server-row drag. Lets folder rows
    /// — which vend no file promise — still register as a local move drag;
    /// Finder ignores this type so a folder dragged out does nothing.
    static let heidrunFileRow = NSPasteboard.PasteboardType("org.tastybytes.heidrun.file-row")
}

/// Per-row actions the AppKit file list invokes (context menu + double
/// click). Closures so `FilesView` keeps owning the sheets/alerts/state.
struct FileRowActions {
    var activate: (RemoteFile) -> Void
    var download: (RemoteFile) -> Void
    var quickLook: (RemoteFile) -> Void
    var isPreviewable: (RemoteFile) -> Bool
    var navigateInto: (RemoteFile) -> Void
    var getInfo: (RemoteFile) -> Void
    var rename: (RemoteFile) -> Void
    var delete: (RemoteFile) -> Void
    /// Download several files at once (folders already filtered out by the
    /// caller). Drives the multi-selection "Download N Items" item.
    var downloadMany: ([RemoteFile]) -> Void
    /// Delete several entries at once. Drives "Delete N Items…".
    var deleteMany: ([RemoteFile]) -> Void
    var uploadHere: () -> Void
    var newFolder: () -> Void
    var refresh: () -> Void
    var secondaryLabel: (RemoteFile) -> String
    /// Upload local URLs dropped from Finder into the current folder.
    var dropURLs: ([URL]) -> Void
    /// Move dragged server rows into a folder row (internal drag-and-drop).
    var move: ([RemoteFile], RemoteFile) -> Void
}

/// AppKit `NSTableView` file list, wrapped for SwiftUI. Replaces the
/// SwiftUI `Table` so rows can be a real drag SOURCE (a SwiftUI `Table`
/// swallows the mouse before an embedded AppKit view sees it). Phase 1
/// here = display / selection / sort / double-click / context menu /
/// drag-IN parity; the row file-promise drag-OUT is layered on next.
struct FileTableView: NSViewRepresentable {
    let files: [RemoteFile]
    @Binding var selection: Set<RemoteFile.ID>
    @Binding var sortAscending: Bool
    @Binding var sortKey: FileSortKey
    let actions: FileRowActions
    /// Streams a file's bytes into the URL the drop's file promise hands
    /// us (runs after the drop, off the drag loop).
    let writeFile: @Sendable (RemoteFile, URL) async throws -> Void
    /// Privilege check for gating mutating menu items (UI hint; the server
    /// still enforces). Defaults to permitting everything so other callers
    /// behave as before.
    var permits: (UserPrivileges) -> Bool = { _ in true }

    @Environment(\.heidrunContentSize) private var contentSize

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = FileShortcutTableView()
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.sizeLastColumnToFit()
        tableView.rowHeight = contentSize.rowHeight
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.doubleClicked(_:))
        tableView.onCommandI = { [weak coordinator = context.coordinator] in
            coordinator?.invokeForSelectedRow { $0.getInfo }
        }
        tableView.onSpace = { [weak coordinator = context.coordinator] in
            coordinator?.invokeForSelectedRow { $0.quickLook }
        }
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.menu = context.coordinator.makeMenu()
        // Accept Finder file URLs (upload) AND our own file-promise row
        // drags (internal move). The internal drag's pasteboard carries
        // file-PROMISE types, not `.fileURL`, so without registering the
        // promise types the table is never a valid destination for its own
        // drag and `validateDrop`/`acceptDrop` never fire.
        tableView.registerForDraggedTypes(
            [.fileURL, .heidrunFileRow]
                + NSFilePromiseReceiver.readableDraggedTypes.map(NSPasteboard.PasteboardType.init(rawValue:))
        )
        // Drag rows OUT to Finder as file promises (downloads on drop).
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        // Drag rows onto a folder row to MOVE them (internal drag).
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)

        let nameColumn = NSTableColumn(identifier: .init(FileSortKey.name.rawValue))
        nameColumn.title = String(localized: "Name", bundle: .module)
        nameColumn.minWidth = 150
        nameColumn.maxWidth = .infinity
        nameColumn.sortDescriptorPrototype = NSSortDescriptor(key: FileSortKey.name.rawValue, ascending: true)
        tableView.addTableColumn(nameColumn)

        let sizeColumn = NSTableColumn(identifier: .init(FileSortKey.size.rawValue))
        sizeColumn.title = String(localized: "Size", bundle: .module)
        sizeColumn.width = 100
        sizeColumn.minWidth = 80
        sizeColumn.maxWidth = 160
        sizeColumn.sortDescriptorPrototype = NSSortDescriptor(key: FileSortKey.size.rawValue, ascending: false)
        tableView.addTableColumn(sizeColumn)

        context.coordinator.tableView = tableView

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 16)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        // Reflect any user-driven `ContentSize` change immediately —
        // body-size overrides (Appearance picker's inline +/-) don't
        // bump rowHeight, but the cell font + icon frame do change,
        // so reloading is gated on the FULL ContentSize value rather
        // than just rowHeight.
        if context.coordinator.lastContentSize != contentSize {
            context.coordinator.lastContentSize = contentSize
            tableView.rowHeight = contentSize.rowHeight
            tableView.reloadData()
        }
        context.coordinator.apply(files: files, to: tableView)
        // Sync selection from SwiftUI → AppKit (guarded so the resulting
        // selection notification doesn't write straight back).
        context.coordinator.beginProgrammaticSelection()
        defer { context.coordinator.endProgrammaticSelection() }
        let targetRows = FileSelectionMapping.rowIndexes(for: selection, in: files)
        if tableView.selectedRowIndexes != targetRows {
            // Empty set deselects all; this also covers the "selection
            // cleared after refresh" case the old code special-cased.
            tableView.selectRowIndexes(targetRows, byExtendingSelection: false)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: FileTableView
        weak var tableView: NSTableView?
        private var files: [RemoteFile] = []
        private var applyingSelection = false
        /// Last `ContentSize` we applied. `nil` = first render.
        var lastContentSize: ContentSize?
        /// `NSFilePromiseProvider.delegate` is weak — retain in-flight
        /// promise delegates until the drag session ends.
        private var promiseDelegates: [FilePromiseDelegate] = []
        /// Rows in the active drag — set at drag start so an internal drop
        /// onto a folder row knows what to move (the file-promise pasteboard
        /// carries no row identity).
        private var draggedRowIndexes = IndexSet()

        init(_ parent: FileTableView) { self.parent = parent }

        func beginProgrammaticSelection() { applyingSelection = true }
        func endProgrammaticSelection() { applyingSelection = false }

        func apply(files newFiles: [RemoteFile], to tableView: NSTableView) {
            guard files != newFiles else { return }
            files = newFiles
            tableView.reloadData()
        }

        // MARK: Data source

        func numberOfRows(in tableView: NSTableView) -> Int { files.count }

        /// Make a row draggable. Files vend an `NSFilePromiseProvider` that
        /// downloads on drop to Finder AND can be moved internally. Folders
        /// can't drag OUT (no promise) but ARE draggable internally to move
        /// into another folder — they carry a marker-only pasteboard item
        /// Finder ignores. Unresolved aliases stay non-draggable.
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row < files.count else { return nil }
            let entry = files[row]
            guard !entry.isUnresolvedAlias else { return nil }
            if entry.isFolder {
                let item = NSPasteboardItem()
                item.setString(entry.name, forType: .heidrunFileRow)
                return item
            }
            let typeID = UTType(filenameExtension: (entry.name as NSString).pathExtension)?.identifier
                ?? UTType.data.identifier
            let write = parent.writeFile
            let delegate = FilePromiseDelegate(fileName: entry.name) { url in
                try await write(entry, url)
            }
            promiseDelegates.append(delegate)
            return NSFilePromiseProvider(fileType: typeID, delegate: delegate)
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            willBeginAt screenPoint: NSPoint,
            forRowIndexes rowIndexes: IndexSet
        ) {
            draggedRowIndexes = rowIndexes
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            promiseDelegates.removeAll()
            draggedRowIndexes = IndexSet()
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard let descriptor = tableView.sortDescriptors.first,
                  let key = descriptor.key, let sortKey = FileSortKey(rawValue: key) else { return }
            parent.sortKey = sortKey
            parent.sortAscending = descriptor.ascending
        }

        // MARK: Delegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < files.count, let column = tableColumn else { return nil }
            let entry = files[row]
            let key = FileSortKey(rawValue: column.identifier.rawValue)
            let identifier = column.identifier
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? FileTableCellView)
                ?? Self.makeCell(identifier: identifier)
            let size = parent.contentSize

            // Per-render font + icon-frame update so a `ContentSize`
            // change (Appearance settings) propagates to recycled cells
            // — `viewFor` is called fresh after `reloadData()`.
            cell.textField?.font = key == .size
                ? .systemFont(ofSize: size.captionPointSize)
                : .systemFont(ofSize: size.bodyPointSize)
            cell.imageWidthConstraint?.constant = size.fileIconSize
            cell.imageHeightConstraint?.constant = size.fileIconSize

            if key == .size {
                cell.textField?.stringValue = parent.actions.secondaryLabel(entry)
                cell.textField?.alignment = .right
                cell.textField?.textColor = .secondaryLabelColor
                cell.imageView?.image = nil
            } else {
                cell.textField?.stringValue = entry.name
                cell.textField?.alignment = .left
                cell.textField?.textColor = .labelColor
                cell.imageView?.image = FileIconRenderer.icon(
                    for: entry,
                    size: NSSize(width: size.fileIconSize, height: size.fileIconSize)
                )
                // Real Finder icons carry their own colours — clear any
                // residual tint from the previous SF-Symbol-only path.
                cell.imageView?.contentTintColor = nil
                cell.imageView?.imageScaling = .scaleProportionallyDown
            }
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView, !applyingSelection else { return }
            parent.selection = FileSelectionMapping.selection(
                forRows: tableView.selectedRowIndexes,
                in: files
            )
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < files.count else { return }
            parent.actions.activate(files[row])
        }

        /// Pull the focused row out of the live selection and feed it to
        /// a `FileRowActions` member. Used by Cmd+I / Spacebar key paths.
        /// Multi-row selection collapses to the first matched row; no-op
        /// when nothing is selected.
        func invokeForSelectedRow(_ pick: (FileRowActions) -> (RemoteFile) -> Void) {
            guard let tableView else { return }
            let row = tableView.selectedRow
            guard row >= 0, row < files.count else { return }
            pick(parent.actions)(files[row])
        }

        // MARK: Drag IN (upload) + internal move

        /// True when the active drag originated in this same table (a row
        /// drag), as opposed to an external Finder drag-in.
        private func isInternalDrag(_ info: NSDraggingInfo) -> Bool {
            (info.draggingSource as? NSTableView) === tableView
        }

        func tableView(
            _ tableView: NSTableView,
            validateDrop info: NSDraggingInfo,
            proposedRow row: Int,
            proposedDropOperation dropOperation: NSTableView.DropOperation
        ) -> NSDragOperation {
            // Internal row drag: only a drop ONTO a folder row (that isn't
            // itself being dragged) is a move.
            if isInternalDrag(info) {
                guard row >= 0, row < files.count else { return [] }
                let target = files[row]
                guard target.isFolder, !target.isUnresolvedAlias,
                      !draggedRowIndexes.contains(row) else { return [] }
                // Retarget a "between rows" proposal onto the folder row.
                if dropOperation == .above {
                    tableView.setDropRow(row, dropOperation: .on)
                }
                return .move
            }
            // External Finder drag-in (upload).
            return info.draggingPasteboard.canReadObject(forClasses: [NSURL.self]) ? .copy : []
        }

        func tableView(
            _ tableView: NSTableView,
            acceptDrop info: NSDraggingInfo,
            row: Int,
            dropOperation: NSTableView.DropOperation
        ) -> Bool {
            if isInternalDrag(info) {
                guard row >= 0, row < files.count else { return false }
                let target = files[row]
                guard target.isFolder else { return false }
                let entries = draggedRowIndexes
                    .filter { $0 < files.count }
                    .map { files[$0] }
                    .filter { $0.id != target.id }
                guard !entries.isEmpty else { return false }
                parent.actions.move(entries, target)
                return true
            }
            guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
                  !urls.isEmpty else { return false }
            parent.actions.dropURLs(urls)
            return true
        }

        // Table Column Sizing

        func sizeToFitWidthOfColumn(_ column: Int, tableView: NSTableView) -> CGFloat {
            let visibleRect = tableView.visibleRect
            let rowRange = tableView.rows(in: visibleRect)
            var minRow = rowRange.location
            var maxRow = rowRange.location + rowRange.length
            minRow = max(0, minRow - 50)
            maxRow = min(tableView.numberOfRows, maxRow + 50)
            let aCol = tableView.tableColumns[column]
            let minWidth = aCol.minWidth
            var width = minWidth
            if minRow <= (maxRow - 1) {
                for idx in minRow ... (maxRow - 1) {
                    if let tcv = tableView.view(atColumn: column, row: idx, makeIfNecessary: true),
                       let tcv = (tcv as? NSTableCellView),
                       let textField = tcv.textField {
                        let fitW = textField.fittingSize.width + 48.0
                        if fitW > width {
                            width = fitW
                        }
                    }
                }
            }
            let min = max(minWidth, width)
            return min
        }

        func tableView(_ tableView: NSTableView, sizeToFitWidthOfColumn column: Int) -> CGFloat {
            sizeToFitWidthOfColumn(column, tableView: tableView)
        }

        // MARK: Context menu

        func makeMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            // We set per-item isEnabled ourselves for privilege gating.
            menu.autoenablesItems = false
            return menu
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView else { return }
            let clicked = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
            guard clicked >= 0, clicked < files.count else { return }
            let clickedEntry = files[clicked]

            // Finder semantics: a right-click on a row that's part of the
            // current multi-selection acts on the whole selection; a click
            // anywhere else acts on just that row.
            let selectedIDs = parent.selection
            if selectedIDs.count > 1, selectedIDs.contains(clickedEntry.id) {
                buildMultiMenu(menu, for: files.filter { selectedIDs.contains($0.id) })
            } else {
                buildSingleMenu(menu, for: clickedEntry)
            }
        }

        private func addItem(to menu: NSMenu, _ title: String, isEnabled: Bool = true, _ handler: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: "")
            item.target = self
            item.isEnabled = isEnabled
            item.representedObject = handler
            menu.addItem(item)
        }

        /// Today's per-item menu, unchanged.
        private func buildSingleMenu(_ menu: NSMenu, for entry: RemoteFile) {
            let actions = parent.actions
            let permits = parent.permits
            if entry.isFolder {
                addItem(to: menu, String(localized: "Open", bundle: .module)) { actions.navigateInto(entry) }
            } else {
                addItem(
                    to: menu,
                    String(localized: "Download", bundle: .module),
                    isEnabled: permits(.downloadFiles)
                ) { actions.download(entry) }
                if actions.isPreviewable(entry) {
                    addItem(to: menu, String(localized: "Quick Look", bundle: .module)) { actions.quickLook(entry) }
                }
            }
            addItem(
                to: menu,
                String(localized: "Upload Here…", bundle: .module),
                isEnabled: permits(.uploadFiles)
            ) { actions.uploadHere() }
            addItem(
                to: menu,
                String(localized: "New Folder…", bundle: .module),
                isEnabled: permits(.createFolders)
            ) { actions.newFolder() }
            menu.addItem(.separator())
            addItem(to: menu, String(localized: "Get Info…", bundle: .module)) { actions.getInfo(entry) }
            addItem(
                to: menu,
                String(localized: "Rename…", bundle: .module),
                isEnabled: permits(entry.isFolder ? .renameFolders : .renameFiles)
            ) { actions.rename(entry) }
            addItem(to: menu, String(localized: "Refresh", bundle: .module)) { actions.refresh() }
            menu.addItem(.separator())
            addItem(
                to: menu,
                String(localized: "Delete…", bundle: .module),
                isEnabled: permits(entry.isFolder ? .deleteFolders : .deleteFiles)
            ) { actions.delete(entry) }
        }

        /// Batch menu for a multi-selection. Single-item actions (Open,
        /// Quick Look, Get Info, Rename) are omitted — they don't apply to
        /// a set. Download appears only when the set contains files.
        private func buildMultiMenu(_ menu: NSMenu, for targets: [RemoteFile]) {
            let actions = parent.actions
            let permits = parent.permits
            let fileTargets = targets.filter { !$0.isFolder }
            let folderTargets = targets.filter { $0.isFolder }
            if !fileTargets.isEmpty {
                addItem(
                    to: menu,
                    String(localized: "Download \(fileTargets.count) Items", bundle: .module),
                    isEnabled: permits(.downloadFiles)
                ) { actions.downloadMany(fileTargets) }
            }
            addItem(
                to: menu,
                String(localized: "Upload Here…", bundle: .module),
                isEnabled: permits(.uploadFiles)
            ) { actions.uploadHere() }
            addItem(
                to: menu,
                String(localized: "New Folder…", bundle: .module),
                isEnabled: permits(.createFolders)
            ) { actions.newFolder() }
            menu.addItem(.separator())
            addItem(to: menu, String(localized: "Refresh", bundle: .module)) { actions.refresh() }
            menu.addItem(.separator())
            // A mixed selection needs both delete bits.
            let canDeleteAll = (fileTargets.isEmpty || permits(.deleteFiles))
                && (folderTargets.isEmpty || permits(.deleteFolders))
            addItem(
                to: menu,
                String(localized: "Delete \(targets.count) Items…", bundle: .module),
                isEnabled: canDeleteAll
            ) { actions.deleteMany(targets) }
        }

        @objc private func menuAction(_ sender: NSMenuItem) {
            (sender.representedObject as? () -> Void)?()
        }

        // MARK: Cell factory

        private static func makeCell(identifier: NSUserInterfaceItemIdentifier) -> FileTableCellView {
            let cell = FileTableCellView()
            cell.identifier = identifier
            let textField = NSTextField(labelWithString: "")
            textField.lineBreakMode = .byTruncatingMiddle
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.font = .systemFont(ofSize: NSFont.systemFontSize)
            cell.textField = textField
            cell.addSubview(textField)

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            cell.imageView = imageView
            cell.addSubview(imageView)

            // Stash the width/height constraints on the cell so `viewFor`
            // can resize the icon as the user-selected `ContentSize`
            // changes — recycled cells keep their original constraint
            // objects between renders.
            let imageWidth = imageView.widthAnchor.constraint(
                equalToConstant: FileIconRenderer.displaySize.width
            )
            let imageHeight = imageView.heightAnchor.constraint(
                equalToConstant: FileIconRenderer.displaySize.height
            )
            cell.imageWidthConstraint = imageWidth
            cell.imageHeightConstraint = imageHeight

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor),
                imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                imageWidth,
                imageHeight,
                textField.leadingAnchor.constraint(
                    equalTo: imageView.trailingAnchor,
                    constant: Spacing.xsmall.rawValue
                ),
                textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor),
                textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
            return cell
        }
    }
}

/// NSTableView that adds two keyboard affordances: Cmd+I → Get Info
/// and Spacebar → Quick Look for the currently-selected row. Anything
/// else falls through to the default NSTableView handler (arrows for
/// selection, Return, etc.).
final class FileShortcutTableView: NSTableView {
    var onCommandI: () -> Void = {}
    var onSpace: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        let chars = event.charactersIgnoringModifiers ?? ""
        if event.modifierFlags.contains(.command), chars == "i" {
            onCommandI()
            return
        }
        if chars == " " {
            onSpace()
            return
        }
        super.keyDown(with: event)
    }
}

/// `NSTableCellView` subclass that holds the icon's width/height
/// constraints as properties so `viewFor` can resize them when the
/// user picks a different `ContentSize` in Settings → Appearance.
/// Recycled cells keep their constraint objects between renders, so
/// pinning them on the cell instance is the simplest way to mutate
/// them without rebuilding the cell.
final class FileTableCellView: NSTableCellView {
    var imageWidthConstraint: NSLayoutConstraint?
    var imageHeightConstraint: NSLayoutConstraint?
}

/// The sortable file columns, identified by a stable string key shared
/// between the NSTableColumn identifier and the sort-descriptor key.
enum FileSortKey: String {
    case name
    case size
}

/// Promise delegate: vends the file name and, after the drop, writes the
/// file on a background operation queue via the supplied async closure.
/// The main thread is free by then, so a main-actor download can't
/// deadlock Finder's drop.
final class FilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate, @unchecked Sendable {
    private let fileName: String
    private let writeFile: @Sendable (URL) async throws -> Void
    private let queue = OperationQueue()

    init(fileName: String, writeFile: @escaping @Sendable (URL) async throws -> Void) {
        self.fileName = fileName
        self.writeFile = writeFile
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        fileName
    }

    func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue { queue }

    func filePromiseProvider(
        _ provider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let writeFile = self.writeFile
        nonisolated(unsafe) let complete = completionHandler
        Task {
            do {
                try await writeFile(url)
                complete(nil)
            } catch {
                complete(error)
            }
        }
    }
}
