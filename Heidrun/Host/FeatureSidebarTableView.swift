import SwiftUI
import AppKit
import HeidrunUI
import CommonTools

/// AppKit `NSTableView` feature picker for the main host sidebar. Replaces
/// a SwiftUI `List(selection:)`: brings the click behaviour, pill styling,
/// and `ContentSize`-aware rows in line with `BookmarkTableView`,
/// `FileTableView`, and `UserTableView`. The feature list is small and
/// static, so the wrapper deliberately omits drag-out, swipe-to-delete,
/// and context menus.
struct FeatureSidebarTableView: NSViewRepresentable {
    let features: [any HeidrunFeature.Type]
    @Binding var selection: String?
    /// Feature identifiers shown but greyed-out and non-selectable — e.g.
    /// the Admin tab for an account without account-admin privileges. A UI
    /// hint only; the server enforces privileges regardless.
    var disabledIdentifiers: Set<String> = []

    @Environment(\.heidrunContentSize) private var contentSize

    /// Sidebar feature picker row height. Sourced from
    /// `ContentSize.sidebarRowHeight` so primary-navigation density
    /// lives in one place across the app.
    static func rowHeight(for size: ContentSize) -> CGFloat {
        size.sidebarRowHeight
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = FirstMouseTableView()
        tableView.style = .plain
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = false
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight(for: contentSize)
        tableView.target = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none

        let column = NSTableColumn(identifier: .init("feature"))
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
        // Guard the WHOLE update window: any reload below can fire
        // `tableViewSelectionDidChange` synchronously, and a write back
        // into our `@Binding` mid-update is the "Modifying state during
        // view update" warning the runtime emits.
        context.coordinator.beginProgrammaticSelection()
        defer { context.coordinator.endProgrammaticSelection() }
        if context.coordinator.lastContentSize != contentSize {
            context.coordinator.lastContentSize = contentSize
            tableView.rowHeight = Self.rowHeight(for: contentSize)
            tableView.reloadData()
        }
        context.coordinator.apply(features: features, disabled: disabledIdentifiers, to: tableView)
        let targetRow = Self.rowIndex(for: selection, in: features)
        let targetRows: IndexSet = targetRow.map { IndexSet(integer: $0) } ?? IndexSet()
        if tableView.selectedRowIndexes != targetRows {
            tableView.selectRowIndexes(targetRows, byExtendingSelection: false)
        }
    }

    private static func rowIndex(for identifier: String?, in features: [any HeidrunFeature.Type]) -> Int? {
        guard let identifier else { return nil }
        return features.firstIndex(where: { $0.identifier == identifier })
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: FeatureSidebarTableView
        weak var tableView: NSTableView?
        private var features: [any HeidrunFeature.Type] = []
        private var lastDisabled: Set<String> = []
        private var applyingSelection = false
        /// Last `ContentSize` we applied. `nil` = first render.
        var lastContentSize: ContentSize?

        init(_ parent: FeatureSidebarTableView) { self.parent = parent }

        func beginProgrammaticSelection() { applyingSelection = true }
        func endProgrammaticSelection() { applyingSelection = false }

        func apply(features newValue: [any HeidrunFeature.Type], disabled: Set<String>, to tableView: NSTableView) {
            let identifiers = newValue.map { $0.identifier }
            let existingIdentifiers = features.map { $0.identifier }
            // Reload when the list OR the disabled set changes — the latter
            // so a row re-greys when privileges arrive after the first render.
            let changed = identifiers != existingIdentifiers || disabled != lastDisabled
            features = newValue
            lastDisabled = disabled
            guard changed else { return }
            tableView.reloadData()
        }

        // MARK: Data source

        func numberOfRows(in tableView: NSTableView) -> Int { features.count }

        /// Disabled feature rows are visible but not selectable.
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            guard row >= 0, row < features.count else { return false }
            return !parent.disabledIdentifiers.contains(features[row].identifier)
        }

        // MARK: Delegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < features.count else { return nil }
            let feature = features[row]
            let identifier = NSUserInterfaceItemIdentifier("featureCell")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? FeatureSidebarCellView)
                ?? FeatureSidebarCellView(identifier: identifier)
            cell.apply(contentSize: parent.contentSize)
            cell.configure(title: feature.displayName, systemImage: feature.systemImage)
            cell.setEnabled(!parent.disabledIdentifiers.contains(feature.identifier))
            return cell
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let identifier = NSUserInterfaceItemIdentifier("featureRowView")
            if let reused = tableView.makeView(withIdentifier: identifier, owner: self) as? FeatureSidebarRowView {
                return reused
            }
            let view = FeatureSidebarRowView()
            view.identifier = identifier
            return view
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView, !applyingSelection else { return }
            let row = tableView.selectedRow
            guard row >= 0, row < features.count else { return }
            let identifier = features[row].identifier
            // Hop to the next runloop tick: AppKit can fire this
            // notification inside SwiftUI's view-update cycle (e.g. when
            // `reloadData` shuffles the selection), and writing to a
            // `@Binding` there is "Modifying state during view update".
            Task {@MainActor [weak self] in
                guard let self else { return }
                if self.parent.selection != identifier {
                    withAnimation(.smooth(duration: 0.67)) {
                        self.parent.selection = identifier
                    }
                }
            }
        }
    }
}

/// Sidebar table that acts on the first click even when focus currently
/// lives in another view (e.g. the chat composer's text view). Without
/// this, SwiftUI's `NavigationSplitView` treats the first click as merely
/// moving the focus section into the sidebar, so selecting a feature took
/// two clicks while a transcript composer held first responder.
private final class FirstMouseTableView: NSTableView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let clickedRow = row(at: convert(event.locationInWindow, from: nil))
        super.mouseDown(with: event)
        // When another responder (notably an editing NSTextView, or the
        // state right after a modal sheet like the server agreement is
        // dismissed) held first responder, AppKit spends the first click
        // transferring first responder to the table and skips the row
        // selection — so the sidebar needed two clicks. Apply the dropped
        // selection ourselves when that happened.
        guard clickedRow >= 0, selectedRow != clickedRow,
              delegate?.tableView?(self, shouldSelectRow: clickedRow) ?? true else { return }
        selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
    }
}

/// Single-line sidebar cell: SF Symbol + display name. Draws its own
/// rounded selection pill (behind the labels) the same way
/// `BookmarkCellView` does, so the highlight is consistent across the
/// three sidebar surfaces. The row view feeds it the selection state.
final class FeatureSidebarCellView: NSTableCellView {
    private let selectionView = NSView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var iconWidthConstraint: NSLayoutConstraint?
    private var iconHeightConstraint: NSLayoutConstraint?
    private var selected = false
    private var emphasized = true
    private var rowEnabled = true
    private var currentSize: ContentSize = .default

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        selectionView.wantsLayer = true
        selectionView.layer?.cornerRadius = .cornerUltraMed
        selectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(selectionView)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: currentSize.bodyPointSize,
            weight: .regular
        )
        iconView.contentTintColor = .labelColor
        addSubview(iconView)

        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.font = .systemFont(ofSize: currentSize.bodyPointSize)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)

        let iconWidth = iconView.widthAnchor.constraint(equalToConstant: currentSize.iconSize)
        let iconHeight = iconView.heightAnchor.constraint(equalToConstant: currentSize.iconSize)
        iconWidthConstraint = iconWidth
        iconHeightConstraint = iconHeight

        NSLayoutConstraint.activate([
            selectionView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.xsmall.rawValue),
            selectionView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.xsmall.rawValue),
            selectionView.topAnchor.constraint(equalTo: topAnchor, constant: Spacing.xxxsmall.rawValue),
            selectionView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Spacing.xxxsmall.rawValue),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Spacing.medium.rawValue),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidth,
            iconHeight,

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Spacing.small.rawValue),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Spacing.medium.rawValue),
            nameLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor)
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, systemImage: String) {
        nameLabel.stringValue = title
        let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        image?.isTemplate = true
        iconView.image = image
    }

    /// Refresh the cell's fonts + icon size for a new `ContentSize`.
    /// Called from `viewFor` so recycled cells pick up the latest
    /// Appearance setting on every render.
    func apply(contentSize: ContentSize) {
        guard contentSize != currentSize else { return }
        currentSize = contentSize
        nameLabel.font = .systemFont(ofSize: contentSize.bodyPointSize)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: contentSize.bodyPointSize,
            weight: .regular
        )
        iconWidthConstraint?.constant = contentSize.iconSize
        iconHeightConstraint?.constant = contentSize.iconSize
    }

    func setSelected(_ isSelected: Bool, emphasized isEmphasized: Bool) {
        guard selected != isSelected || emphasized != isEmphasized else { return }
        selected = isSelected
        emphasized = isEmphasized
        updateAppearance()
    }

    /// Grey-out for a feature the account can't use (e.g. Admin without
    /// account-admin privileges). The row stays visible; selection is
    /// blocked by the table delegate.
    func setEnabled(_ isEnabled: Bool) {
        guard rowEnabled != isEnabled else { return }
        rowEnabled = isEnabled
        updateAppearance()
    }

    private func updateAppearance() {
        let fill: NSColor
        if selected && rowEnabled {
            fill = .textBackgroundColor
        } else {
            fill = .clear
        }
        selectionView.layer?.backgroundColor = fill.cgColor
        let onEmphasized = selected && rowEnabled
        let baseColor: NSColor = rowEnabled ? .labelColor : .tertiaryLabelColor
        nameLabel.textColor = onEmphasized ? .controlAccentColor : baseColor
        iconView.contentTintColor = onEmphasized ? .controlAccentColor : baseColor
    }
}

/// Row view that suppresses the system selection highlight and hands the
/// selection state to its cell, which draws the pill itself. Mirrors
/// `BookmarkRowView`.
final class FeatureSidebarRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        // Intentionally empty — the cell draws the selection pill.
    }

    override var isSelected: Bool {
        didSet { propagateSelection() }
    }

    override var isEmphasized: Bool {
        didSet { propagateSelection() }
    }

    override func layout() {
        super.layout()
        propagateSelection()
    }

    private func propagateSelection() {
        for case let cell as FeatureSidebarCellView in subviews {
            cell.setSelected(isSelected, emphasized: isEmphasized)
        }
    }
}
