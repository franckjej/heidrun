import SwiftUI
import AppKit
import HeidrunCore
import HeidrunUI
import CommonTools

/// Per-row callbacks invoked by the AppKit thread outline (selection,
/// context menu, drag-out payload). Closures so `ThreadedNewsScreen`
/// keeps owning the sheets / alerts / clipboard formatter.
struct ThreadOutlineActions {
    /// User clicked / keyboard-selected a row — drive `openThread`.
    var open: (NewsThread) -> Void
    /// Items for the per-row context menu. Built lazily on right-click;
    /// each entry's handler runs when the user picks it.
    var menuItems: (NewsThread) -> [ThreadMenuItem]
    /// Plain-text payload for the drag-out (`.txt` file + clipboard text).
    var clipboardText: (NewsThread) -> String
    /// Drag-out filename base (no extension).
    var clipboardTitle: (NewsThread) -> String
}

/// One row in the AppKit context menu. `separator` short-circuits the
/// title/handler — used only for visual grouping.
struct ThreadMenuItem {
    let title: String
    let role: Role
    let handler: () -> Void

    enum Role { case normal, destructive, separator }

    static var separator: ThreadMenuItem {
        ThreadMenuItem(title: "", role: .separator, handler: {})
    }

    static func normal(_ title: String, _ handler: @escaping () -> Void) -> ThreadMenuItem {
        ThreadMenuItem(title: title, role: .normal, handler: handler)
    }

    static func destructive(_ title: String, _ handler: @escaping () -> Void) -> ThreadMenuItem {
        ThreadMenuItem(title: title, role: .destructive, handler: handler)
    }
}

/// AppKit `NSOutlineView` thread tree, wrapped for SwiftUI. Replaces the
/// SwiftUI `List + ForEach(buildThreadTree(...))` so:
///   * the reply hierarchy gets native disclosure triangles (no manual
///     `Spacer().frame(width: depth * 24)` indent),
///   * scrolling reuses `NSTableCellView` instances instead of paying
///     the SwiftUI per-row `.onTapGesture` / `.onDrag` / `.contextMenu`
///     diff cost on every row,
///   * rows are a real drag SOURCE for the per-post `.txt` (SwiftUI
///     `.onDrag` inside a List + HSplitView sometimes loses the gesture).
struct ThreadOutlineView: NSViewRepresentable {
    let threads: [NewsThread]
    let selectedThreadID: UInt16?
    let actions: ThreadOutlineActions

    @Environment(\.heidrunContentSize) private var contentSize

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let outlineView = NSOutlineView()
        outlineView.style = .inset
        outlineView.headerView = nil
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = true
        outlineView.indentationPerLevel = Spacing.medium.rawValue
        outlineView.indentationMarkerFollowsCell = true
        outlineView.autosaveExpandedItems = false
        outlineView.autoresizesOutlineColumn = false
        outlineView.rowHeight = contentSize.rowHeight
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        outlineView.menu = context.coordinator.makeMenu()
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)

        let column = NSTableColumn(identifier: .init("subject"))
        column.title = ""
        column.minWidth = 200
        column.maxWidth = .infinity
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        context.coordinator.outlineView = outlineView

        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let outlineView = scrollView.documentView as? NSOutlineView else { return }
        if context.coordinator.lastContentSize != contentSize {
            context.coordinator.lastContentSize = contentSize
            outlineView.rowHeight = contentSize.rowHeight
            outlineView.reloadData()
        }
        context.coordinator.apply(threads: threads, to: outlineView)
        context.coordinator.beginProgrammaticSelection()
        defer { context.coordinator.endProgrammaticSelection() }
        let targetRow = context.coordinator.row(for: selectedThreadID, in: outlineView)
        if outlineView.selectedRow != targetRow {
            if targetRow >= 0 {
                outlineView.selectRowIndexes(
                    IndexSet(integer: targetRow),
                    byExtendingSelection: false
                )
                outlineView.scrollRowToVisible(targetRow)
            } else {
                outlineView.deselectAll(nil)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
        var parent: ThreadOutlineView
        weak var outlineView: NSOutlineView?
        var lastContentSize: ContentSize?
        private var roots: [ThreadOutlineNode] = []
        private var nodesByID: [UInt16: ThreadOutlineNode] = [:]
        private var applyingSelection = false

        init(_ parent: ThreadOutlineView) { self.parent = parent }

        func beginProgrammaticSelection() { applyingSelection = true }
        func endProgrammaticSelection() { applyingSelection = false }

        func apply(threads: [NewsThread], to outlineView: NSOutlineView) {
            let snapshot = ThreadOutlineNode.makeTree(threads)
            // NSOutlineView identifies items by pointer. If we replace
            // `roots` / `nodesByID` with fresh node instances every call
            // — even when threads didn't change — the outline view still
            // holds the OLD pointers in its display, and `row(forItem:)`
            // on a new node returns -1. That makes the selection sync
            // think the selected row vanished and call `deselectAll` —
            // every body-pane refresh (e.g. `isLoadingBody` toggling
            // after a click) wipes the selection. Early-return before
            // touching the live node graph when the signature matches.
            let oldSig = roots.flatMap(\.signature)
            let newSig = snapshot.roots.flatMap(\.signature)
            guard oldSig != newSig else { return }
            roots = snapshot.roots
            nodesByID = snapshot.lookup
            outlineView.reloadData()
            outlineView.expandItem(nil, expandChildren: true)
        }

        func row(for threadID: UInt16?, in outlineView: NSOutlineView) -> Int {
            guard let identifier = threadID,
                  let node = nodesByID[identifier]
            else { return -1 }
            return outlineView.row(forItem: node)
        }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if let node = item as? ThreadOutlineNode {
                return node.children.count
            }
            return roots.count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if let node = item as? ThreadOutlineNode {
                return node.children[index]
            }
            return roots[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? ThreadOutlineNode)?.children.isEmpty == false
        }

        // MARK: Drag OUT

        func outlineView(
            _ outlineView: NSOutlineView,
            pasteboardWriterForItem item: Any
        ) -> NSPasteboardWriting? {
            guard let node = item as? ThreadOutlineNode else { return nil }
            return ThreadPostPasteboardWriter(
                title: parent.actions.clipboardTitle(node.thread),
                text: parent.actions.clipboardText(node.thread)
            )
        }

        // MARK: Delegate

        func outlineView(
            _ outlineView: NSOutlineView,
            viewFor tableColumn: NSTableColumn?,
            item: Any
        ) -> NSView? {
            guard let node = item as? ThreadOutlineNode else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("ThreadCell")
            let cell = (outlineView.makeView(withIdentifier: identifier, owner: self) as? ThreadOutlineCellView)
                ?? Self.makeCell(identifier: identifier)
            cell.applyContentSize(parent.contentSize)
            cell.configure(with: node.thread, isRoot: node.parentID == 0)
            return cell
        }

        func outlineView(
            _ outlineView: NSOutlineView,
            rowViewForItem item: Any
        ) -> NSTableRowView? {
            let identifier = NSUserInterfaceItemIdentifier("ThreadRow")
            if let pooled = outlineView.makeView(withIdentifier: identifier, owner: self)
                as? AccentSelectionRowView {
                return pooled
            }
            let row = AccentSelectionRowView()
            row.identifier = identifier
            return row
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView, !applyingSelection else { return }
            let row = outlineView.selectedRow
            guard row >= 0,
                  let node = outlineView.item(atRow: row) as? ThreadOutlineNode
            else { return }
            parent.actions.open(node.thread)
        }

        // MARK: Context menu

        func makeMenu() -> NSMenu {
            let menu = NSMenu()
            menu.delegate = self
            return menu
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let outlineView else { return }
            let clickedRow = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
            guard clickedRow >= 0,
                  let node = outlineView.item(atRow: clickedRow) as? ThreadOutlineNode
            else { return }
            for entry in parent.actions.menuItems(node.thread) {
                switch entry.role {
                case .separator:
                    menu.addItem(.separator())
                case .normal, .destructive:
                    let item = NSMenuItem(
                        title: entry.title,
                        action: #selector(handleMenu(_:)),
                        keyEquivalent: ""
                    )
                    item.target = self
                    item.representedObject = entry.handler
                    menu.addItem(item)
                }
            }
        }

        @objc private func handleMenu(_ sender: NSMenuItem) {
            (sender.representedObject as? () -> Void)?()
        }

        // MARK: Cell factory

        private static func makeCell(identifier: NSUserInterfaceItemIdentifier) -> ThreadOutlineCellView {
            let cell = ThreadOutlineCellView()
            cell.identifier = identifier
            cell.buildSubviews()
            return cell
        }
    }
}

// MARK: - Tree node

/// Reference-type node so `NSOutlineView`'s pointer-identity item
/// tracking works (the outline view stores `Any` items but compares by
/// pointer for expansion/selection state).
final class ThreadOutlineNode {
    let thread: NewsThread
    let parentID: UInt16
    let children: [ThreadOutlineNode]

    init(thread: NewsThread, parentID: UInt16, children: [ThreadOutlineNode]) {
        self.thread = thread
        self.parentID = parentID
        self.children = children
    }

    /// Cheap structural signature for change detection: id, parent, and
    /// title (so an edit-in-place reloads).
    var signature: [String] {
        let title = thread.elements.first?.title ?? ""
        let mine = "\(thread.threadID)|\(parentID)|\(title)"
        return [mine] + children.flatMap(\.signature)
    }

    /// Build the parent→children tree, orphan-promoting threads whose
    /// `parentID` isn't in the input. Matches `buildThreadTree` (which
    /// the SwiftUI version used) and sorts siblings by `postDate`.
    static func makeTree(
        _ threads: [NewsThread]
    ) -> (roots: [ThreadOutlineNode], lookup: [UInt16: ThreadOutlineNode]) {
        let knownIDs = Set(threads.map(\.threadID))
        let byParent: [UInt16: [NewsThread]] = Dictionary(grouping: threads) { thread in
            knownIDs.contains(thread.parentID) ? thread.parentID : 0
        }
        var lookup: [UInt16: ThreadOutlineNode] = [:]
        func walk(parent: UInt16) -> [ThreadOutlineNode] {
            let siblings = (byParent[parent] ?? []).sorted { $0.postDate < $1.postDate }
            return siblings.map { thread in
                let node = ThreadOutlineNode(
                    thread: thread,
                    parentID: parent,
                    children: walk(parent: thread.threadID)
                )
                lookup[thread.threadID] = node
                return node
            }
        }
        let roots = walk(parent: 0)
        return (roots, lookup)
    }
}

// MARK: - Cell

final class ThreadOutlineCellView: NSTableCellView {
    private let titleField = InertLabel()
    private let authorField = InertLabel()
    private let sizeField = InertLabel()
    private let dateField = InertLabel()
    private let iconView = InertImageView()
    /// Track root-vs-reply so `backgroundStyle.didSet` knows what tint to
    /// restore when the selection flips off (root posts use the accent
    /// colour; replies use the secondary label colour).
    private var isRootPost = true

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyBackgroundStyle() }
    }

    private func applyBackgroundStyle() {
        let emphasised = backgroundStyle == .emphasized
        titleField.textColor = emphasised ? .white : .labelColor
        let secondary: NSColor = emphasised
            ? NSColor.white.withAlphaComponent(0.85)
            : .secondaryLabelColor
        authorField.textColor = secondary
        sizeField.textColor = secondary
        dateField.textColor = secondary
        if emphasised {
            iconView.contentTintColor = .white
        } else {
            iconView.contentTintColor = isRootPost ? .controlAccentColor : .secondaryLabelColor
        }
    }

    func buildSubviews() {
        for view in [iconView, titleField, authorField, sizeField, dateField] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        textField = titleField

        titleField.lineBreakMode = .byTruncatingTail
        titleField.font = .systemFont(ofSize: NSFont.systemFontSize)
        titleField.textColor = .labelColor

        authorField.lineBreakMode = .byTruncatingTail
        authorField.textColor = .secondaryLabelColor
        authorField.font = .systemFont(ofSize: NSFont.systemFontSize)

        sizeField.font = .monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
        sizeField.textColor = .secondaryLabelColor
        sizeField.alignment = .right

        dateField.font = .monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
        dateField.textColor = .secondaryLabelColor
        dateField.lineBreakMode = .byTruncatingTail

        iconView.imageScaling = .scaleProportionallyDown
        iconView.contentTintColor = .secondaryLabelColor

        let hairline: CGFloat = Spacing.xsmall.rawValue
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            titleField.leadingAnchor.constraint(
                equalTo: iconView.trailingAnchor,
                constant: hairline
            ),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.trailingAnchor.constraint(
                lessThanOrEqualTo: authorField.leadingAnchor,
                constant: -hairline
            ),

            authorField.trailingAnchor.constraint(
                equalTo: sizeField.leadingAnchor,
                constant: -hairline
            ),
            authorField.centerYAnchor.constraint(equalTo: centerYAnchor),
            authorField.widthAnchor.constraint(lessThanOrEqualToConstant: 140),

            sizeField.trailingAnchor.constraint(
                equalTo: dateField.leadingAnchor,
                constant: -hairline
            ),
            sizeField.centerYAnchor.constraint(equalTo: centerYAnchor),
            sizeField.widthAnchor.constraint(equalToConstant: 60),

            dateField.trailingAnchor.constraint(equalTo: trailingAnchor),
            dateField.centerYAnchor.constraint(equalTo: centerYAnchor),
            dateField.widthAnchor.constraint(equalToConstant: 110)
        ])
    }

    func applyContentSize(_ size: ContentSize) {
        let body = NSFont.systemFont(ofSize: size.bodyPointSize)
        let mono = NSFont.monospacedDigitSystemFont(
            ofSize: size.bodyPointSize,
            weight: .regular
        )
        titleField.font = body
        authorField.font = body
        sizeField.font = mono
        dateField.font = mono
    }

    func configure(with thread: NewsThread, isRoot: Bool) {
        isRootPost = isRoot
        let element = thread.elements.first
        titleField.stringValue = element?.title.nonEmpty ?? "Untitled"
        iconView.image = NSImage(
            systemSymbolName: isRoot ? "text.bubble.fill" : "arrow.turn.down.right",
            accessibilityDescription: nil
        )
        applyBackgroundStyle()

        if let author = element?.author.nonEmpty {
            authorField.stringValue = author
            authorField.isHidden = false
        } else {
            authorField.stringValue = ""
            authorField.isHidden = true
        }

        if let size = element?.size, size > 0 {
            sizeField.stringValue = "\(size) B"
            sizeField.isHidden = false
        } else {
            sizeField.stringValue = ""
            sizeField.isHidden = true
        }

        if let display = thread.postDate.displayableAbsolute {
            dateField.stringValue = display
            dateField.isHidden = false
        } else {
            dateField.stringValue = ""
            dateField.isHidden = true
        }
    }
}

// MARK: - Pasteboard writer

/// One-shot writer for a row's drag-out: a `.txt` file Finder/Mail can
/// receive, plus the same body as plain text (TextEdit, BBEdit, the
/// system clipboard). The temp file is written lazily when the drop
/// destination reads `.fileURL` — small enough (one news post) that a
/// synchronous write inside the pasteboard read is fine.
final class ThreadPostPasteboardWriter: NSObject, NSPasteboardWriting {
    private let title: String
    private let text: String

    init(title: String, text: String) {
        self.title = title
        self.text = text
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [.string, .fileURL]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case .string:
            return text
        case .fileURL:
            let safe = TextFileExport.sanitize(title)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(safe)
                .appendingPathExtension("txt")
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                return url.absoluteString
            } catch {
                return nil
            }
        default:
            return nil
        }
    }
}
