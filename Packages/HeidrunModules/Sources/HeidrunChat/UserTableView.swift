import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HeidrunCore
import HeidrunUI
import CommonTools

/// Per-row actions the AppKit user roster invokes. Closures so the
/// surrounding SwiftUI `UserListInspector` keeps owning the behaviour.
struct UserRowActions {
    var sendMessage: (User) -> Void
    var startPrivateChat: (User) -> Void
    var getInfo: (User) -> Void
    var editAccount: (User) -> Void
    var disconnect: (User) -> Void
}

/// AppKit `NSTableView` user roster, wrapped for SwiftUI. A SwiftUI
/// `Table` with a per-row drag-out fights its own click selection — a
/// repeat click on the same row gets swallowed by the drag gesture, so
/// re-selecting becomes unreliable. `NSTableView` gives solid click
/// selection alongside row drag-out. Mirrors `BookmarkTableView` /
/// `FileTableView`. Single selection (the selected user's socket).
struct UserTableView: NSViewRepresentable {
    let users: [User]
    @Binding var selection: UInt16?
    let actions: UserRowActions

    @Environment(\.heidrunContentSize) private var contentSize

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// User rows want more vertical breathing room than a plain file
    /// row — they carry an avatar and an away-status overlay. Sourced
    /// from `ContentSize.userListRowHeight` (= `iconSize * 2`) so the
    /// density ladder lives in one place in CommonTools.
    static func rowHeight(for size: ContentSize) -> CGFloat {
        size.userListRowHeight
    }

    func makeNSView(context: Context) -> NSScrollView {
        let tableView = RosterTableView()
        // `.inset` gives the rounded-rect selection highlight with side
        // margins (matches the old SwiftUI `.inset` Table look).
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.headerView = nil
        tableView.rowHeight = Self.rowHeight(for: contentSize)
        // A subtle hairline between rows.
        tableView.gridStyleMask = .solidHorizontalGridLineMask
        tableView.gridColor = .separatorColor
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.doubleClicked(_:))
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.menu = context.coordinator.makeMenu()
        // Drag a row OUT to Finder as a `.txt` of the user's basic info.
        tableView.setDraggingSourceOperationMask(.copy, forLocal: false)
        tableView.backgroundColor = .clear

        let column = NSTableColumn(identifier: .init("user"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        context.coordinator.tableView = tableView
        tableView.onCopy = { [weak coordinator = context.coordinator] in
            coordinator?.copySelectedUser()
        }
        tableView.canCopy = { [weak tableView] in (tableView?.selectedRow ?? -1) >= 0 }

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
        // `ContentSize` changes from any direction (preset OR body
        // override) need to reload — body overrides don't bump
        // rowHeight (icon size + row height stay preset-pinned) but
        // the cell font does, so the recycled cells need a fresh
        // `viewFor` call to pick the new font up.
        let targetRowHeight = Self.rowHeight(for: contentSize)
        if context.coordinator.lastContentSize != contentSize {
            context.coordinator.lastContentSize = contentSize
            tableView.rowHeight = targetRowHeight
            tableView.reloadData()
        }
        // Guard the whole reload + select so neither writes selection back
        // into SwiftUI mid-update.
        context.coordinator.beginProgrammaticSelection()
        defer { context.coordinator.endProgrammaticSelection() }
        context.coordinator.apply(users: users, to: tableView)

        if let row = users.firstIndex(where: { $0.socket == selection }) {
            if tableView.selectedRow != row {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
        } else if tableView.selectedRow != -1 {
            tableView.deselectAll(nil)
        }
    }

    /// `NSTableView` that handles the standard Copy command (⌘C / Edit ▸
    /// Copy). AppKit only routes `copy:` here while the table is the first
    /// responder, so it's focus-scoped for free — it never steals ⌘C from
    /// the chat transcript or a text field, and (unlike a SwiftUI
    /// `.onCopyCommand`) it doesn't disturb click selection.
    final class RosterTableView: NSTableView, NSMenuItemValidation {
        var onCopy: (() -> Void)?
        var canCopy: () -> Bool = { false }

        @objc func copy(_ sender: Any?) { onCopy?() }

        func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
            if menuItem.action == #selector(copy(_:)) { return canCopy() }
            return true
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: UserTableView
        weak var tableView: NSTableView?
        private var users: [User] = []
        private var applyingSelection = false
        /// Last `ContentSize` we applied. `nil` = "haven't applied
        /// anything yet" so the first updateNSView always reloads.
        var lastContentSize: ContentSize?
        /// `NSFilePromiseProvider.delegate` is weak — retain in-flight
        /// delegates until the drag session ends.
        private var promiseDelegates: [UserInfoPromiseDelegate] = []

        init(_ parent: UserTableView) { self.parent = parent }

        func beginProgrammaticSelection() { applyingSelection = true }
        func endProgrammaticSelection() { applyingSelection = false }

        func apply(users newValue: [User], to tableView: NSTableView) {
            guard users != newValue else { return }
            users = newValue
            tableView.reloadData()
        }

        // MARK: Data source

        func numberOfRows(in tableView: NSTableView) -> Int { users.count }

        /// Drag a row OUT to Finder as a `<nickname>.txt` of the basic info
        /// (now including the emoji avatar via `UserInfoText`). Written off
        /// the drag loop.
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row < users.count else { return nil }
            let delegate = UserInfoPromiseDelegate(user: users[row])
            promiseDelegates.append(delegate)
            return NSFilePromiseProvider(fileType: UTType.plainText.identifier, delegate: delegate)
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
            guard row < users.count else { return nil }
            let identifier = NSUserInterfaceItemIdentifier("userCell")
            let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? UserCellView)
                ?? UserCellView(identifier: identifier)
            cell.apply(contentSize: parent.contentSize)
            cell.configure(user: users[row])
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView, !applyingSelection else { return }
            let row = tableView.selectedRow
            parent.selection = (row >= 0 && row < users.count) ? users[row].socket : nil
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            let row = sender.clickedRow
            guard row >= 0, row < users.count else { return }
            parent.actions.sendMessage(users[row])
        }

        /// Copy "<emoji> <nickname>" to the pasteboard.
        func copy(_ user: User) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(UserInfoText.displayName(user), forType: .string)
        }

        /// ⌘C target — copies the currently-selected row.
        func copySelectedUser() {
            guard let tableView,
                  tableView.selectedRow >= 0,
                  tableView.selectedRow < users.count else { return }
            copy(users[tableView.selectedRow])
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
            guard row >= 0, row < users.count else { return }
            let user = users[row]

            func add(_ title: String, _ handler: @escaping () -> Void) {
                let item = NSMenuItem(title: title, action: #selector(menuAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = handler
                menu.addItem(item)
            }

            add(String(localized: "Send Message…", bundle: .module)) { [actions = parent.actions] in
                actions.sendMessage(user)
            }
            add(String(localized: "Start Chat", bundle: .module)) { [actions = parent.actions] in
                actions.startPrivateChat(user)
            }
            add(String(localized: "Get Info…", bundle: .module)) { [actions = parent.actions] in
                actions.getInfo(user)
            }
            add(String(localized: "Edit Account…", bundle: .module)) { [actions = parent.actions] in
                actions.editAccount(user)
            }
            menu.addItem(.separator())
            add(String(localized: "Copy Nickname", bundle: .module)) { [weak self] in
                self?.copy(user)
            }
            menu.addItem(.separator())
            add(String(localized: "Disconnect…", bundle: .module)) { [actions = parent.actions] in
                actions.disconnect(user)
            }
        }

        @objc private func menuAction(_ sender: NSMenuItem) {
            (sender.representedObject as? () -> Void)?()
        }
    }
}

/// Roster cell: avatar (emoji / bundled icon / SF Symbol fallback) +
/// nickname (server-tinted) over an optional status suffix. Uses the
/// standard `NSTableView` selection highlight, flipping the labels to
/// white while the row is emphasized.
final class UserCellView: NSTableCellView {
    private let avatarImageView = NSImageView()
    private let avatarEmojiLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private var nameColor: NSColor = .labelColor

    private var avatarWidthConstraint: NSLayoutConstraint?
    private var avatarHeightConstraint: NSLayoutConstraint?
    private var currentSize: ContentSize = .default

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.imageScaling = .scaleProportionallyUpOrDown

        avatarEmojiLabel.translatesAutoresizingMaskIntoConstraints = false
        avatarEmojiLabel.font = .systemFont(ofSize: currentSize.bodyPointSize + 2)
        avatarEmojiLabel.alignment = .center
        avatarEmojiLabel.backgroundColor = .clear
        avatarEmojiLabel.isBordered = false

        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.font = .systemFont(ofSize: currentSize.bodyPointSize)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(avatarImageView)
        addSubview(avatarEmojiLabel)
        addSubview(nameLabel)

        let avatarWidth = avatarImageView.widthAnchor.constraint(
            equalToConstant: currentSize.iconSize
        )
        let avatarHeight = avatarImageView.heightAnchor.constraint(
            equalToConstant: currentSize.iconSize
        )
        avatarWidthConstraint = avatarWidth
        avatarHeightConstraint = avatarHeight

        NSLayoutConstraint.activate([
            avatarImageView.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: Spacing.xsmall.rawValue
            ),
            avatarImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            avatarWidth,
            avatarHeight,

            avatarEmojiLabel.centerXAnchor.constraint(equalTo: avatarImageView.centerXAnchor),
            avatarEmojiLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0.5),

            nameLabel.leadingAnchor.constraint(
                equalTo: avatarImageView.trailingAnchor, constant: Spacing.xsmall.rawValue
            ),
            nameLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -Spacing.xsmall.rawValue
            ),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    /// Re-apply font + avatar-frame for the picked `ContentSize`.
    /// Called from `viewFor` so recycled cells pick up the latest
    /// Appearance setting on every render.
    func apply(contentSize: ContentSize) {
        guard contentSize != currentSize else { return }
        currentSize = contentSize
        nameLabel.font = .systemFont(ofSize: contentSize.bodyPointSize)
        avatarEmojiLabel.font = .systemFont(ofSize: contentSize.bodyPointSize + 2)
        avatarWidthConstraint?.constant = contentSize.iconSize
        avatarHeightConstraint?.constant = contentSize.iconSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(user: User) {
        if let emoji = EmojiAvatar.sanitized(user.emoji) {
            avatarEmojiLabel.stringValue = emoji
            avatarEmojiLabel.isHidden = false
            avatarImageView.isHidden = true
        } else if let cgImage = IconCatalog.shared.icons.cgImage(forID: Int(user.icon)) {
            avatarImageView.image = NSImage(cgImage: cgImage, size: NSSize(width: 16, height: 16))
            avatarImageView.contentTintColor = nil
            avatarImageView.isHidden = false
            avatarEmojiLabel.isHidden = true
        } else {
            // Fallback when the iconID isn't in the bundled catalog.
            let symbol = NSImage(systemSymbolName: "person.crop.circle.fill", accessibilityDescription: nil)
            avatarImageView.image = symbol?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(hierarchicalColor: Self.rowTint(for: user))
            )
            avatarImageView.isHidden = false
            avatarEmojiLabel.isHidden = true
        }

        let dim: CGFloat = user.status.flags.contains(.away) ? 0.5 : 1.0
        avatarImageView.alphaValue = dim
        avatarEmojiLabel.alphaValue = dim

        nameLabel.stringValue = user.nickname.isEmpty
            ? String(localized: "(no name)", bundle: .module)
            : user.nickname
        nameColor = Self.nameTint(for: user)

        updateColors()
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { updateColors() }
    }

    private func updateColors() {
        let emphasized = backgroundStyle == .emphasized
        nameLabel.textColor = emphasized ? .white : nameColor
    }

    // MARK: Tints (NSColor mirrors of UserListInspector's SwiftUI tints)

    static func nameTint(for user: User) -> NSColor {
        if user.status.flags.contains(.away) { return .secondaryLabelColor }
        if let palette = UserColorPalette.color(forID: user.status.color) { return NSColor(palette) }
        if user.status.flags.contains(.admin) || user.status.flags.contains(.sysOp) { return .systemRed }
        return .labelColor
    }

    static func rowTint(for user: User) -> NSColor {
        if user.status.flags.contains(.admin) || user.status.flags.contains(.sysOp) { return .systemRed }
        if user.status.flags.contains(.away) { return .secondaryLabelColor }
        return .controlAccentColor
    }
}

/// Writes a single user's basic info `.txt` to the promised URL after the
/// drop, off the drag loop. Mirrors `BookmarkPromiseDelegate`.
final class UserInfoPromiseDelegate: NSObject, NSFilePromiseProviderDelegate, @unchecked Sendable {
    private let nickname: String
    private let text: String
    private let queue = OperationQueue()

    @MainActor
    init(user: User) {
        self.nickname = user.nickname.isEmpty ? "User" : user.nickname
        self.text = UserInfoText.basic(user)
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        "\(nickname).txt"
    }

    func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue { queue }

    func filePromiseProvider(
        _ provider: NSFilePromiseProvider,
        writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}
