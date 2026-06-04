import SwiftUI
import AppKit
import HeidrunCore
import HeidrunUI
import CommonTools

/// Per-row data the conversation list renders. Bundled here so the
/// AppKit cell doesn't have to call back into the view-model per
/// render — SwiftUI computes the snapshot once per re-render.
struct ConversationDisplay: Identifiable, Equatable {
    let id: UInt16
    let nickname: String?
    let iconID: UInt16?
    let emoji: String?
    let isOnline: Bool
    let hasUnread: Bool
    let lastMessagePreview: String?
}

/// AppKit `NSTableView` wrap of the conversations list. Replaces the
/// SwiftUI sidebar `List` so:
///   * the selection capsule stays emphasised when focus moves to the
///     message composer / a context menu (via `AccentSelectionRowView`),
///   * the row metrics match the rest of Heidrun's AppKit lists,
///   * future drag-out / swipe-to-delete have a real `NSTableView` to
///     attach to (per the `feedback_appkit_table_for_lists` rule).
///
/// The cell hosts a SwiftUI `ConversationRow` so we keep the existing
/// emoji + Hotline-icon + fallback rendering exactly as the previous
/// `UserIcon` view drew it.
struct ConversationsTableView: NSViewRepresentable {
    let conversations: [ConversationDisplay]
    let selectedID: UInt16?
    let onSelect: (UInt16) -> Void
    let onDelete: (UInt16) -> Void
    /// Plain-text payload for the drag-out (`.txt` file + clipboard
    /// text). `nil` makes the row not draggable.
    let transcriptText: (UInt16) -> String?
    /// Drag-out filename base (no extension). Defaults to the peer's
    /// nickname.
    let transcriptTitle: (UInt16) -> String

    @Environment(\.heidrunContentSize) private var contentSize

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = NSTableView()
        tableView.style = .inset
        tableView.headerView = nil
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.rowHeight = contentSize.rowHeight + Spacing.small.rawValue
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.backgroundColor = .clear
        // Drag rows OUT as plain-text + .txt file. Local drags are off
        // — re-ordering conversations isn't meaningful here.
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)

        let column = NSTableColumn(identifier: .init("conversation"))
        column.minWidth = 200
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
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        if context.coordinator.lastContentSize != contentSize {
            context.coordinator.lastContentSize = contentSize
            tableView.rowHeight = contentSize.rowHeight + Spacing.small.rawValue
            tableView.reloadData()
        }
        context.coordinator.apply(conversations: conversations, to: tableView)
        context.coordinator.beginProgrammaticSelection()
        defer { context.coordinator.endProgrammaticSelection() }
        let targetRow = context.coordinator.row(for: selectedID)
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
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: ConversationsTableView
        weak var tableView: NSTableView?
        var lastContentSize: ContentSize?
        private var conversations: [ConversationDisplay] = []
        private var applyingSelection = false

        init(_ parent: ConversationsTableView) { self.parent = parent }

        func beginProgrammaticSelection() { applyingSelection = true }
        func endProgrammaticSelection() { applyingSelection = false }

        func apply(conversations new: [ConversationDisplay], to tableView: NSTableView) {
            guard conversations != new else { return }
            conversations = new
            tableView.reloadData()
        }

        func row(for identifier: UInt16?) -> Int {
            guard let identifier else { return -1 }
            return conversations.firstIndex { $0.id == identifier } ?? -1
        }

        // MARK: Data source

        func numberOfRows(in tableView: NSTableView) -> Int { conversations.count }

        // MARK: Delegate

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < conversations.count else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("ConversationCell")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? ConversationCellView)
                ?? Self.makeCell(identifier: identifier)
            cell.configure(with: conversations[row])
            return cell
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            let identifier = NSUserInterfaceItemIdentifier("ConversationRow")
            if let pooled = tableView.makeView(withIdentifier: identifier, owner: self)
                as? AccentSelectionRowView {
                return pooled
            }
            let view = AccentSelectionRowView()
            view.identifier = identifier
            return view
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView, !applyingSelection else { return }
            let row = tableView.selectedRow
            guard row >= 0, row < conversations.count else { return }
            parent.onSelect(conversations[row].id)
        }

        // MARK: Swipe to delete

        func tableView(
            _ tableView: NSTableView,
            rowActionsForRow row: Int,
            edge: NSTableView.RowActionEdge
        ) -> [NSTableViewRowAction] {
            guard edge == .trailing, row >= 0, row < conversations.count else { return [] }
            let socket = conversations[row].id
            let delete = NSTableViewRowAction(
                style: .destructive,
                title: String(localized: "Delete", bundle: .module)
            ) { [weak self] _, _ in
                guard let self else { return }
                self.parent.onDelete(socket)
            }
            return [delete]
        }

        // MARK: Drag OUT

        func tableView(
            _ tableView: NSTableView,
            pasteboardWriterForRow row: Int
        ) -> NSPasteboardWriting? {
            guard row >= 0, row < conversations.count else { return nil }
            let socket = conversations[row].id
            guard let text = parent.transcriptText(socket) else { return nil }
            return ConversationPasteboardWriter(
                title: parent.transcriptTitle(socket),
                text: text
            )
        }

        // MARK: Cell factory

        private static func makeCell(identifier: NSUserInterfaceItemIdentifier) -> ConversationCellView {
            let cell = ConversationCellView()
            cell.identifier = identifier
            cell.buildSubviews()
            return cell
        }
    }
}

// MARK: - Cell

/// AppKit cell that hosts a SwiftUI `ConversationRow`. We host SwiftUI
/// rather than rebuilding the icon-with-fallback chain in AppKit — the
/// `UserIcon` cascade (emoji → Hotline catalog → SF Symbol) is
/// already polished in SwiftUI. To keep the table-view selection from
/// flashing off the moment a label inside the SwiftUI content grabs
/// first responder, `hitTest` returns the cell itself for any point
/// in bounds — clicks land on the cell and bubble straight to the
/// row / table view.
final class ConversationCellView: NSTableCellView {
    private var hosting: NSHostingView<ConversationRow>?
    private var conversation: ConversationDisplay?
    private var isEmphasised = false

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            isEmphasised = backgroundStyle == .emphasized
            updateHostedRow()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        // Take the hit ourselves so the hosted SwiftUI content can't
        // steal first responder from the table view.
        return self
    }

    func buildSubviews() {
        let row = ConversationRow(conversation: nil, isSelected: false)
        let host = NSHostingView(rootView: row)
        host.translatesAutoresizingMaskIntoConstraints = false
        addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor),
            host.topAnchor.constraint(equalTo: topAnchor),
            host.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        hosting = host
    }

    func configure(with conversation: ConversationDisplay) {
        self.conversation = conversation
        updateHostedRow()
    }

    private func updateHostedRow() {
        hosting?.rootView = ConversationRow(
            conversation: conversation,
            isSelected: isEmphasised
        )
    }
}

// MARK: - SwiftUI row

/// SwiftUI rendering of one conversation row. Read by the AppKit cell
/// through `NSHostingView`; selection-aware so the unread dot and
/// secondary text stay visible against the accent capsule.
struct ConversationRow: View {
    let conversation: ConversationDisplay?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: Spacing.xsmall.rawValue) {
            UserIcon(
                id: conversation?.iconID,
                emoji: conversation?.emoji,
                size: 24
            )
            .opacity((conversation?.isOnline ?? true) ? 1.0 : 0.4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xxsmall.rawValue) {
                    Text(conversation?.nickname ?? "Unknown user")
                        .heidrunBody()
                        .fontWeight((conversation?.hasUnread ?? false) ? .semibold : .regular)
                        .foregroundStyle(isSelected ? Color.white : .primary)
                        .lineLimit(1)
                    if conversation?.isOnline == false {
                        Text("offline")
                            .heidrunCaption()
                            .foregroundStyle(
                                isSelected
                                    ? AnyShapeStyle(Color.white.opacity(0.8))
                                    : AnyShapeStyle(.tertiary)
                            )
                    }
                }
                if let preview = conversation?.lastMessagePreview {
                    Text(preview)
                        .heidrunCaption()
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Spacing.xxsmall.rawValue)

            if conversation?.hasUnread == true {
                Circle()
                    .fill(isSelected ? Color.white : Color.accentColor)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, .xsmall)
        .padding(.vertical, .xxsmall)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pasteboard writer

/// One-shot writer for a conversation's drag-out: a `.txt` file Finder
/// or Mail can receive, plus the same transcript as plain text for
/// TextEdit / BBEdit / the system clipboard. The temp file is written
/// lazily inside `pasteboardPropertyList(forType: .fileURL)` so we don't
/// pay the I/O cost unless the drop destination asks for a file.
final class ConversationPasteboardWriter: NSObject, NSPasteboardWriting {
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

// MARK: - UserIcon (vendored from MessagesView)

/// Renders a user's emoji avatar if present, else the bundled Hotline
/// icon for `id`, falling back to an SF Symbol when the catalog has no
/// entry. Identical to the previous private `UserIcon` in `MessagesView`
/// — moved here so the AppKit cell and any future detail-header use
/// the same render path.
struct UserIcon: View {
    let id: UInt16?
    var emoji: String?
    var size: CGFloat = 24

    var body: some View {
        if let emoji = EmojiAvatar.sanitized(emoji) {
            Text(emoji)
                .font(.system(size: size * 0.85))
                .fixedSize()
                .frame(width: size, height: size)
        } else if let id, let cgImage = IconCatalog.shared.icons.cgImage(forID: Int(id)) {
            Image(decorative: cgImage, scale: 1, orientation: .up)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "person.crop.square")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }
}
