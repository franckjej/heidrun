import Foundation
import Observation
import AppKit
import HeidrunCore
import HeidrunUI

/// Per-user direct-message threads.
///
/// Subscribes to `HotlineEvent.messageReceived` and groups incoming
/// messages by the remote user's `socket`. Outgoing replies are routed
/// through `sendPrivateMessage` and immediately appended to the local
/// thread so the UI feels responsive without waiting for the server echo
/// (Hotline doesn't echo private messages back).
@Observable
@MainActor
public final class MessagesViewModel {
    public enum Direction: Sendable, Hashable {
        case incoming
        case outgoing
    }

    public struct Message: Sendable, Identifiable, Hashable {
        public let id: UUID
        public let receivedAt: Date
        public let text: String
        public let direction: Direction

        public init(
            text: String,
            direction: Direction,
            receivedAt: Date = Date(),
            id: UUID = UUID()
        ) {
            self.id = id
            self.receivedAt = receivedAt
            self.text = text
            self.direction = direction
        }
    }

    public struct Thread: Sendable, Identifiable, Hashable {
        public let id: UInt16
        public var messages: [Message]
        public var hasUnread: Bool
        /// Last seen nickname for this socket; falls back to here when
        /// the user has logged off and the live user-list no longer
        /// contains them. `icon` mirrors the same idea.
        public var cachedNickname: String?
        public var cachedIcon: UInt16?
        /// Last seen emoji avatar, cached like `cachedNickname`/`cachedIcon`
        /// so a logged-off correspondent keeps their emoji in the thread.
        public var cachedEmoji: String?

        public init(
            id: UInt16,
            messages: [Message] = [],
            hasUnread: Bool = false,
            cachedNickname: String? = nil,
            cachedIcon: UInt16? = nil,
            cachedEmoji: String? = nil
        ) {
            self.id = id
            self.messages = messages
            self.hasUnread = hasUnread
            self.cachedNickname = cachedNickname
            self.cachedIcon = cachedIcon
            self.cachedEmoji = cachedEmoji
        }
    }

    /// Threads in most-recent-activity-first order.
    public private(set) var threads: [Thread] = []

    /// `id` of the thread currently shown in the detail pane.
    public var activeThreadID: UInt16?

    /// Two-way bound input field for the active thread.
    public var draft: String = ""

    /// Live user roster used to resolve a socket → nickname/icon and
    /// online/offline status. Held weakly so the connection handle can
    /// own both VMs without retaining cycles.
    private weak var userList: UserListViewModel?

    /// Fired every time an incoming PM lands. The host wires this to
    /// auto-switch to the Messages module and surface the originating
    /// thread; tests just leave it nil.
    public var onIncomingMessage: (@MainActor (UInt16) -> Void)?

    private let events: AsyncStream<HotlineEvent>
    private let sendMessage: @Sendable (String, UInt16) async throws -> Void
    private var observationTask: Task<Void, Never>?

    public init(
        events: AsyncStream<HotlineEvent>,
        sendMessage: @escaping @Sendable (String, UInt16) async throws -> Void,
        userList: UserListViewModel? = nil
    ) {
        self.events = events
        self.sendMessage = sendMessage
        self.userList = userList
    }

    public convenience init(client: any HotlineClient, userList: UserListViewModel? = nil) {
        self.init(
            events: client.events,
            sendMessage: { [client] message, socket in
                try await client.sendPrivateMessage(message, to: socket)
            },
            userList: userList
        )
    }

    /// Start `observe()` in a managed Task. Idempotent — calling twice
    /// does nothing. Pair with `cancel()` from the connection handle so
    /// thread history survives module switches.
    public func start() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self] in
            await self?.observe()
        }
    }

    /// Stop the observation task started by `start()`. Safe to call
    /// when no task is running.
    public func cancel() {
        observationTask?.cancel()
        observationTask = nil
    }

    public func observe() async {
        for await event in events {
            if case let .messageReceived(socket, message) = event {
                appendIncoming(message: message, from: socket)
            }
        }
    }

    // MARK: - Roster lookup

    /// Live nickname when the user is still in the roster, otherwise
    /// the nickname captured the last time we exchanged a message with
    /// them. Returns nil only for sockets we've never seen.
    public func nickname(for socket: UInt16) -> String? {
        if let live = userList?.users.first(where: { $0.socket == socket }) {
            return live.nickname.isEmpty ? nil : live.nickname
        }
        return threads.first(where: { $0.id == socket })?.cachedNickname
    }

    /// Live icon ID when the user is still in the roster, otherwise the
    /// icon captured the last time we exchanged a message with them.
    public func icon(for socket: UInt16) -> UInt16? {
        if let live = userList?.users.first(where: { $0.socket == socket }) {
            return live.icon
        }
        return threads.first(where: { $0.id == socket })?.cachedIcon
    }

    public func emoji(for socket: UInt16) -> String? {
        if let live = userList?.users.first(where: { $0.socket == socket }) {
            return live.emoji
        }
        return threads.first(where: { $0.id == socket })?.cachedEmoji
    }

    /// True when the remote user is still in the live roster.
    public func isOnline(socket: UInt16) -> Bool {
        userList?.users.contains { $0.socket == socket } ?? false
    }

    /// Mark the active thread as read.
    public func markActiveThreadRead() {
        guard let id = activeThreadID, let i = threads.firstIndex(where: { $0.id == id }) else { return }
        threads[i].hasUnread = false
        refreshDockBadge()
    }

    /// Send the current draft to the active thread, then clear it.
    public func sendDraft() async throws {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let socket = activeThreadID else { return }
        try await sendMessage(text, socket)
        appendOutgoing(message: text, to: socket)
        draft = ""
    }

    /// Open or focus a thread with the given user.
    public func openThread(with socket: UInt16) {
        if !threads.contains(where: { $0.id == socket }) {
            threads.insert(Thread(id: socket), at: 0)
        }
        activeThreadID = socket
        markActiveThreadRead()
    }

    /// Drop a single conversation from the local cache. Hotline has no
    /// server-side concept of "delete a conversation" — private messages
    /// aren't persisted by the server — so this just clears the local
    /// thread. If it was the active one, the detail pane falls back to
    /// the "Pick a conversation" empty state.
    public func deleteConversation(socket: UInt16) {
        threads.removeAll { $0.id == socket }
        if activeThreadID == socket {
            activeThreadID = nil
            draft = ""
        }
        refreshDockBadge()
    }

    /// Clear every conversation. Same caveat as `deleteConversation`:
    /// local cache only.
    public func deleteAll() {
        threads.removeAll()
        activeThreadID = nil
        draft = ""
        refreshDockBadge()
    }

    /// Plain-text rendering of a single conversation, suitable for the
    /// drag-out payload and the clipboard. One line per message, prefixed
    /// with the timestamp and the nickname (or "Me" for outgoing).
    public func transcript(for socket: UInt16) -> String? {
        guard let thread = threads.first(where: { $0.id == socket }) else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let peer = nickname(for: socket) ?? "Unknown user"
        let lines = thread.messages.map { message -> String in
            let when = formatter.string(from: message.receivedAt)
            let who = message.direction == .outgoing ? "Me" : peer
            return "[\(when)] \(who): \(message.text)"
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    private func appendIncoming(message: String, from socket: UInt16) {
        let line = Message(text: message, direction: .incoming)
        upsert(socket: socket) { thread in
            thread.messages.append(line)
            thread.hasUnread = (socket != activeThreadID)
        }
        // Dock attention: bounce only when the user can't see the new
        // message — either the app isn't active or the active thread
        // is a different conversation. The system stops the bounce
        // automatically when the app gains focus.
        let isVisible = NSApp.isActive && activeThreadID == socket
        if !isVisible, Self.dockBounceEnabled() {
            NSApp.requestUserAttention(.criticalRequest)
        }
        refreshDockBadge()
        onIncomingMessage?(socket)
    }

    /// Mirror the unread-thread count onto `NSApp.dockTile.badgeLabel`.
    /// Empty string clears the badge — `nil` would leave the previous
    /// label in place. When the user has disabled the badge in Settings,
    /// we clear the label so a previously-set value doesn't linger.
    private func refreshDockBadge() {
        guard Self.dockBadgeEnabled() else {
            NSApp.dockTile.badgeLabel = ""
            return
        }
        let unread = threads.lazy.filter(\.hasUnread).count
        NSApp.dockTile.badgeLabel = unread > 0 ? String(unread) : ""
    }

    // MARK: - Settings keys
    //
    // These string literals are mirrored from
    // `Heidrun/App/AppStorageKeys.swift` — kept here so HeidrunMessages
    // doesn't have to depend on the app target. If you rename either
    // key, change BOTH places.
    private static let dockBounceKey = "Heidrun.dockBounceOnPrivateMessage"
    private static let dockBadgeKey = "Heidrun.dockBadgeForUnreadMessages"

    private static func dockBounceEnabled() -> Bool {
        UserDefaults.standard.object(forKey: dockBounceKey) as? Bool ?? true
    }

    private static func dockBadgeEnabled() -> Bool {
        UserDefaults.standard.object(forKey: dockBadgeKey) as? Bool ?? true
    }

    private func appendOutgoing(message: String, to socket: UInt16) {
        let line = Message(text: message, direction: .outgoing)
        upsert(socket: socket) { thread in
            thread.messages.append(line)
        }
    }

    private func upsert(socket: UInt16, mutate: (inout Thread) -> Void) {
        let live = userList?.users.first(where: { $0.socket == socket })
        if let i = threads.firstIndex(where: { $0.id == socket }) {
            var thread = threads.remove(at: i)
            mutate(&thread)
            // Refresh the cached identity so a later disconnect doesn't
            // strand the thread with a stale label.
            if let live {
                thread.cachedNickname = live.nickname
                thread.cachedIcon = live.icon
                thread.cachedEmoji = live.emoji
            }
            threads.insert(thread, at: 0)
        } else {
            var thread = Thread(
                id: socket,
                cachedNickname: live?.nickname,
                cachedIcon: live?.icon,
                cachedEmoji: live?.emoji
            )
            mutate(&thread)
            threads.insert(thread, at: 0)
        }
    }
}
