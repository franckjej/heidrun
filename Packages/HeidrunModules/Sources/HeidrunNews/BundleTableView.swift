import SwiftUI
import AppKit
import HeidrunCore
import HeidrunUI
import CommonTools

/// Per-row callbacks for the AppKit bundle list (single-click navigation
/// + context menu). Mirrors `ThreadOutlineActions` so the two news
/// panes share the same shape.
struct BundleListActions {
    /// Single-click handler. Folders should descend; categories should
    /// load their threads. Caller decides which.
    var navigate: (NewsBundle) -> Void
    /// Menu entries built lazily on right-click.
    var menuItems: (NewsBundle) -> [ThreadMenuItem]
}

/// AppKit `NSTableView` wrap of the threaded-news left pane (folders +
/// categories at the current path). Replaces the SwiftUI `List` so it
/// shares chrome / row metrics with `ThreadOutlineView` on the right —
/// without this the first folder row and the first thread row sat at
/// different Y because plain `List` and `.inset` `NSOutlineView` have
/// different top insets.
struct BundleTableView: NSViewRepresentable {
    let bundles: [NewsBundle]
    let selectedBundleID: NewsBundle.ID?
    let actions: BundleListActions

    @Environment(\.heidrunContentSize) private var contentSize

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.style = .inset
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.rowHeight = contentSize.rowHeight
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.menu = context.coordinator.makeMenu()
        tableView.backgroundColor = .clear

        let column = NSTableColumn(identifier: .init("bundle"))
        column.minWidth = 100
        column.maxWidth = .infinity
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        context.coordinator.tableView = tableView

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 2)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        if context.coordinator.lastContentSize != contentSize {
            context.coordinator.lastContentSize = contentSize
            tableView.rowHeight = contentSize.rowHeight
            tableView.reloadData()
        }
        context.coordinator.apply(bundles: bundles, to: tableView)
        context.coordinator.beginProgrammaticSelection()
        defer { context.coordinator.endProgrammaticSelection() }
        let targetRow = context.coordinator.row(for: selectedBundleID)
        if tableView.selectedRow != targetRow {
            if targetRow >= 0 {
                tableView.selectRowIndexes(
                    IndexSet(integer: targetRow),
                    byExtendingSelection: false
                )
            } else {
                tableView.deselectAll(nil)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: BundleTableView
        weak var tableView: NSTableView?
        var lastContentSize: ContentSize?
        private var bundles: [NewsBundle] = []
        private var applyingSelection = false

        init(_ parent: BundleTableView) { self.parent = parent }

        func beginProgrammaticSelection() { applyingSelection = true }
        func endProgrammaticSelection() { applyingSelection = false }

        func apply(bundles newBundles: [NewsBundle], to tableView: NSTableView) {
            guard bundles != newBundles else { return }
            bundles = newBundles
            tableView.reloadData()
        }

        func row(for identifier: NewsBundle.ID?) -> Int {
            guard let identifier else { return -1 }
            return bundles.firstIndex { $0.id == identifier } ?? -1
        }

        // MARK: Data source

        func numberOfRows(in tableView: NSTableView) -> Int { bundles.count }

        // MARK: Delegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < bundles.count else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("BundleCell")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? BundleCellView)
                ?? Self.makeCell(identifier: identifier)
            cell.applyContentSize(parent.contentSize)
            cell.configure(with: bundles[row])
            return cell
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let identifier = NSUserInterfaceItemIdentifier("BundleRow")
            if let pooled = tableView.makeView(withIdentifier: identifier, owner: self)
                as? AccentSelectionRowView {
                return pooled
            }
            let view = AccentSelectionRowView()
            view.identifier = identifier
            return view
        }

        // MARK: Selection drives navigation

        /// One-shot: when the selected row changes (single click on a
        /// new row, or keyboard arrow), drive the navigation handler.
        /// Re-clicking the same row is a no-op — `selectionDidChange`
        /// doesn't fire, so a re-click on the currently-selected
        /// category doesn't reload its threads and clobber the right
        /// pane's thread selection.
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView, !applyingSelection else { return }
            let row = tableView.selectedRow
            guard row >= 0, row < bundles.count else { return }
            parent.actions.navigate(bundles[row])
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
            let clicked = tableView.clickedRow >= 0 ? tableView.clickedRow : tableView.selectedRow
            guard clicked >= 0, clicked < bundles.count else { return }
            for entry in parent.actions.menuItems(bundles[clicked]) {
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

        private static func makeCell(identifier: NSUserInterfaceItemIdentifier) -> BundleCellView {
            let cell = BundleCellView()
            cell.identifier = identifier
            cell.buildSubviews()
            return cell
        }
    }
}

// MARK: - Cell

/// Cell view: SF Symbol on the leading edge, title in the middle, an
/// optional `(N)` count trailing for categories that advertise a size.
/// Layout mirrors `ThreadOutlineCellView` so both panes share row
/// metrics and the first rows sit on the same Y baseline.
final class BundleCellView: NSTableCellView {
    private let titleField = InertLabel()
    private let countField = InertLabel()
    private let iconView = InertImageView()
    private var bundleKind: NewsBundle.Kind = .bundle

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { applyBackgroundStyle() }
    }

    func buildSubviews() {
        for view in [iconView, titleField, countField] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        textField = titleField

        titleField.lineBreakMode = .byTruncatingTail
        titleField.font = .systemFont(ofSize: NSFont.systemFontSize)
        titleField.textColor = .labelColor

        countField.font = .monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize,
            weight: .regular
        )
        countField.textColor = .secondaryLabelColor
        countField.alignment = .right

        iconView.imageScaling = .scaleProportionallyDown

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
                lessThanOrEqualTo: countField.leadingAnchor,
                constant: -hairline
            ),

            countField.trailingAnchor.constraint(equalTo: trailingAnchor),
            countField.centerYAnchor.constraint(equalTo: centerYAnchor),
            countField.widthAnchor.constraint(lessThanOrEqualToConstant: 60)
        ])
    }

    func applyContentSize(_ size: ContentSize) {
        titleField.font = .systemFont(ofSize: size.bodyPointSize)
        countField.font = .monospacedDigitSystemFont(
            ofSize: size.bodyPointSize,
            weight: .regular
        )
    }

    func configure(with bundle: NewsBundle) {
        bundleKind = bundle.kind
        titleField.stringValue = bundle.title.isEmpty
            ? String(localized: "(untitled)", bundle: .module)
            : bundle.title
        iconView.image = NSImage(
            systemSymbolName: bundle.kind == .bundle ? "folder.fill" : "tray.full.fill",
            accessibilityDescription: nil
        )
        if bundle.size > 0 {
            countField.stringValue = "(\(bundle.size))"
            countField.isHidden = false
        } else {
            countField.stringValue = ""
            countField.isHidden = true
        }
        applyBackgroundStyle()
    }

    private func applyBackgroundStyle() {
        let emphasised = backgroundStyle == .emphasized
        titleField.textColor = emphasised ? .white : .labelColor
        countField.textColor = emphasised
            ? NSColor.white.withAlphaComponent(0.85)
            : .secondaryLabelColor
        if emphasised {
            iconView.contentTintColor = .white
        } else {
            iconView.contentTintColor = bundleKind == .bundle
                ? .controlAccentColor
                : .secondaryLabelColor
        }
    }
}
