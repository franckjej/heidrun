import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HeidrunCore
import HeidrunBookmarks
import HeidrunUI
import CommonTools

struct BookmarkRowActions {
    /// Direct connect (single-row double-click / context menu).
    var connect: (Bookmark) -> Void
    /// Multi-row double-click: receiver claims the current window for
    /// the first entry and fans the rest across fresh host windows.
    var connectMany: ([Bookmark]) -> Void
    /// Routed through the confirmation dialog.
    var delete: (Bookmark) -> Void
}

/// AppKit `NSTableView` bookmark roster wrapped for SwiftUI. Replaces a
/// SwiftUI `List`: only NSTableView gives reliable click selection
/// alongside trackpad swipe-to-delete (via `rowActionsForRow`) and row
/// drag-out — all three fought each other in SwiftUI.
struct BookmarkTableView: NSViewRepresentable {
    let bookmarks: [Bookmark]
    @Binding var selection: Set<Bookmark.ID>
    let actions: BookmarkRowActions

    @Environment(\.heidrunContentSize) private var contentSize

    /// Density-ladder source — `ContentSize.bookmarkRowHeight` lives in
    /// CommonTools so the rest of the app sees the same ladder.
    static func rowHeight(for size: ContentSize) -> CGFloat {
        size.bookmarkRowHeight
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = true
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight(for: contentSize)
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.doubleClicked(_:))
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.menu = context.coordinator.makeMenu()
        // Drag rows OUT to Finder as `.heidrunbookmarks` (no passwords).
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.backgroundColor = .clear

        let column = NSTableColumn(identifier: .init("bookmark"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        context.coordinator.tableView = tableView

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.backgroundColor = .clear
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        // Body-size overrides don't change rowHeight but DO change cell
        // fonts, so gate on the full ContentSize rather than rowHeight.
        if context.coordinator.lastContentSize != contentSize {
            context.coordinator.lastContentSize = contentSize
            tableView.rowHeight = Self.rowHeight(for: contentSize)
            tableView.reloadData()
        }
        context.coordinator.apply(bookmarks: bookmarks, to: tableView)
        // Sync SwiftUI → AppKit, guarded so the resulting notification
        // doesn't write straight back.
        context.coordinator.beginProgrammaticSelection()
        defer { context.coordinator.endProgrammaticSelection() }
        let targetRows = Self.rowIndexes(for: selection, in: bookmarks)
        if tableView.selectedRowIndexes != targetRows {
            tableView.selectRowIndexes(targetRows, byExtendingSelection: false)
        }
    }

    private static func rowIndexes(for selection: Set<Bookmark.ID>, in bookmarks: [Bookmark]) -> IndexSet {
        var indexes = IndexSet()
        for (index, mark) in bookmarks.enumerated() where selection.contains(mark.id) {
            indexes.insert(index)
        }
        return indexes
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: BookmarkTableView
        weak var tableView: NSTableView?
        private var bookmarks: [Bookmark] = []
        private var applyingSelection = false
        var lastContentSize: ContentSize?
        /// `NSFilePromiseProvider.delegate` is weak — retain in-flight
        /// promise delegates until the drag session ends.
        private var promiseDelegates: [BookmarkPromiseDelegate] = []

        init(_ parent: BookmarkTableView) { self.parent = parent }

        func beginProgrammaticSelection() { applyingSelection = true }
        func endProgrammaticSelection() { applyingSelection = false }

        func apply(bookmarks newValue: [Bookmark], to tableView: NSTableView) {
            guard bookmarks != newValue else { return }
            bookmarks = newValue
            tableView.reloadData()
        }

        // MARK: Data source

        func numberOfRows(in tableView: NSTableView) -> Int { bookmarks.count }

        /// Drag OUT to Finder as `.heidrunbookmarks` (no passwords). Vends
        /// a file promise written off the drag loop.
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row < bookmarks.count else { return nil }
            let delegate = BookmarkPromiseDelegate(bookmark: bookmarks[row])
            promiseDelegates.append(delegate)
            return NSFilePromiseProvider(fileType: UTType.heidrunBookmarks.identifier, delegate: delegate)
        }

        func tableView(
            _ tableView: NSTableView,
            draggingSession session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            promiseDelegates.removeAll()
        }

        // MARK: Delegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < bookmarks.count else { return nil }
            let mark = bookmarks[row]
            let identifier = NSUserInterfaceItemIdentifier("bookmarkCell")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? BookmarkCellView)
                ?? BookmarkCellView(identifier: identifier)
            cell.apply(contentSize: parent.contentSize)
            cell.configure(
                title: mark.settings.name.isEmpty ? mark.settings.address : mark.settings.name,
                subtitle: mark.settings.login
            )
            return cell
        }

        /// Custom row view so the selection highlight's corner radius
        /// matches the system-drawn swipe Delete button.
        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let identifier = NSUserInterfaceItemIdentifier("bookmarkRowView")
            if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? BookmarkRowView {
                return reused
            }
            let view = BookmarkRowView()
            view.identifier = identifier
            return view
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView, !applyingSelection else { return }
            var ids = Set<Bookmark.ID>()
            for row in tableView.selectedRowIndexes where row < bookmarks.count {
                ids.insert(bookmarks[row].id)
            }
            parent.selection = ids
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            let clickedRow = sender.clickedRow
            guard clickedRow >= 0, clickedRow < bookmarks.count else { return }
            let selectedRows = sender.selectedRowIndexes
            // Double-clicking inside a multi-row selection means "connect
            // all of these". Otherwise it's a one-bookmark connect.
            if selectedRows.contains(clickedRow), selectedRows.count > 1 {
                let marks = selectedRows.compactMap { row -> Bookmark? in
                    row < bookmarks.count ? bookmarks[row] : nil
                }
                parent.actions.connectMany(marks)
            } else {
                parent.actions.connect(bookmarks[clickedRow])
            }
        }

        /// Native trailing swipe-to-delete (two-finger trackpad swipe).
        /// Routed through the confirmation dialog; collapse immediately.
        func tableView(
            _ tableView: NSTableView,
            rowActionsForRow row: Int,
            edge: NSTableView.RowActionEdge
        ) -> [NSTableViewRowAction] {
            guard edge == .trailing, row < bookmarks.count else { return [] }
            let mark = bookmarks[row]
            let delete = NSTableViewRowAction(
                style: .destructive,
                title: String(localized: "Delete")
            ) { [weak self] _, _ in
                self?.tableView?.rowActionsVisible = false
                self?.parent.actions.delete(mark)
            }
            return [delete]
        }

        // MARK: Context menu

        func makeMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            return menu
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let tableView else { return }
            let row = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
            guard row >= 0, row < bookmarks.count else { return }
            let mark = bookmarks[row]

            func add(_ title: String, _ handler: @escaping () -> Void) {
                let item = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = handler
                menu.addItem(item)
            }

            add(String(localized: "Connect")) { [actions = parent.actions] in actions.connect(mark) }
            menu.addItem(.separator())
            add(String(localized: "Delete…")) { [actions = parent.actions] in actions.delete(mark) }
        }

        @objc private func menuAction(_ sender: NSMenuItem) {
            (sender.representedObject as? () -> Void)?()
        }
    }
}

/// Two-line bookmark cell (name + login). Draws its OWN selection pill
/// behind the labels so the highlight slides with the cell during the
/// swipe-to-delete reveal instead of sitting static behind the button.
/// Radius = `height / 2` to match the system swipe Delete pill.
final class BookmarkCellView: NSTableCellView {
    private let selectionView = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let loginLabel = NSTextField(labelWithString: "")
    private var selected = false
    private var emphasized = true
    private var currentSize: ContentSize = .default

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        selectionView.wantsLayer = true
        selectionView.layer?.cornerRadius = 12
        selectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(selectionView)

        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.font = .systemFont(ofSize: currentSize.bodyPointSize)
        loginLabel.lineBreakMode = .byTruncatingTail
        loginLabel.font = .systemFont(ofSize: currentSize.captionPointSize)
        if let image = NSImage(named: "BookmarkIcon") {
            image.isTemplate = true
            imageView = NSImageView(image: image)
            imageView?.contentTintColor = .systemRed
            imageView?.translatesAutoresizingMaskIntoConstraints = false
            addSubview(imageView!)
        }
        let stack = NSStackView(views: [nameLabel, loginLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        guard let imageView else { return }
        NSLayoutConstraint.activate([
            // 6pt pill inset so the rounded background breathes around
            // the two-line text. (Was 3pt — looked glued to the row.)
            selectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            selectionView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            selectionView.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            selectionView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            imageView.leadingAnchor.constraint(equalTo: stack.trailingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            imageView.heightAnchor.constraint(equalToConstant: 32),
            imageView.widthAnchor.constraint(equalToConstant: 24),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        updateAppearance()
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, subtitle: String) {
        nameLabel.stringValue = title
        loginLabel.stringValue = subtitle
        loginLabel.isHidden = subtitle.isEmpty
    }

    /// Recycled cells pick up the latest Appearance setting on render.
    func apply(contentSize: ContentSize) {
        guard contentSize != currentSize else { return }
        currentSize = contentSize
        nameLabel.font = .systemFont(ofSize: contentSize.bodyPointSize)
        loginLabel.font = .systemFont(ofSize: contentSize.captionPointSize)
    }

    func setSelected(_ isSelected: Bool, emphasized isEmphasized: Bool) {
        guard selected != isSelected || emphasized != isEmphasized else { return }
        selected = isSelected
        emphasized = isEmphasized
        updateAppearance()
    }

    private func updateAppearance() {
        // Pill is always present so the cell slides over the revealed
        // Delete as a rounded shape, not a square edge. Unselected →
        // clear so it rounds the swipe but is invisible at rest.
        let fill: NSColor
        if selected {
            fill = emphasized ? .selectedContentBackgroundColor : .unemphasizedSelectedContentBackgroundColor
        } else {
            fill = .clear
        }
        selectionView.layer?.backgroundColor = fill.cgColor
        let onEmphasized = selected && emphasized
        nameLabel.textColor = onEmphasized ? .white : .labelColor
        loginLabel.textColor = onEmphasized ? NSColor.white.withAlphaComponent(0.75) : .secondaryLabelColor
    }
}

/// Suppresses the system selection highlight and hands selection state to
/// the cell, which draws its own pill — that's what lets the highlight
/// slide with the swipe reveal instead of sitting static behind the button.
final class BookmarkRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        // Cell draws the selection pill.
    }

    override var isSelected: Bool {
        didSet { propagateSelection() }
    }

    override var isEmphasized: Bool {
        didSet { propagateSelection() }
    }

    override func layout() {
        super.layout()
        // Catches cells added/reused after `isSelected` was set.
        propagateSelection()
    }

    private func propagateSelection() {
        for case let cell as BookmarkCellView in subviews {
            cell.setSelected(isSelected, emphasized: isEmphasized)
        }
    }
}

/// Writes one bookmark's `.heidrunbookmarks` archive (no passwords) to
/// the promised URL after the drop, off the drag loop.
final class BookmarkPromiseDelegate: NSObject, NSFilePromiseProviderDelegate, @unchecked Sendable {
    private let bookmark: Bookmark
    private let queue = OperationQueue()

    init(bookmark: Bookmark) { self.bookmark = bookmark }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        BookmarkExport(bookmarks: [bookmark]).suggestedFileName + ".heidrunbookmarks"
    }

    func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue { queue }

    func filePromiseProvider(
        _ provider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        do {
            let data = try BookmarkExport.archiveData(for: [bookmark])
            try data.write(to: url, options: .atomic)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}
