import Foundation
import Observation
import HeidrunCore
import HeidrunUI

/// View-model behind the public/private chat surface. Filters the host's
/// `HotlineEvent` stream down to chat lines for one scope (public chat
/// by default, or one private `ChatID`), accumulates them, and forwards
/// outgoing chat through the supplied sender closure.
@Observable
@MainActor
public final class ChatViewModel {
    /// One displayable chat line. Wire format is a single string
    /// ` nickname: body`. We split on the first `: ` (the nickname can
    /// itself contain colons — "silver:box" — but those aren't followed
    /// by a space) so the view can right-align the sender column.
    public struct Line: Sendable, Identifiable, Hashable {
        public let id: UUID
        public let receivedAt: Date
        public let sender: String?
        public let body: String
        public let isAction: Bool
        /// Client-synthesised state line ("Erika entered"). The view
        /// renders these in muted italics without a sender column and
        /// can hide them via `showChatJoinLeave`.
        public let isSystem: Bool

        public init(
            sender: String?,
            body: String,
            isAction: Bool = false,
            isSystem: Bool = false,
            receivedAt: Date = Date(),
            id: UUID = UUID()
        ) {
            self.id = id
            self.receivedAt = receivedAt
            self.sender = sender
            self.body = body
            self.isAction = isAction
            self.isSystem = isSystem
        }

        public init(rawMessage: String, isAction: Bool) {
            self.id = UUID()
            self.receivedAt = Date()
            self.isAction = isAction
            self.isSystem = false

            if isAction {
                self.sender = nil
                self.body = rawMessage
                return
            }

            if let range = rawMessage.range(of: ": ") {
                self.sender = String(rawMessage[..<range.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                self.body = String(rawMessage[range.upperBound...])
            } else {
                self.sender = nil
                self.body = rawMessage
            }
        }
    }

    public private(set) var lines: [Line] = []

    /// Updated by `privateChatSubjectChanged` events for private chats;
    /// can be set explicitly for public chat (vanilla Hotline has no
    /// matching event there).
    public private(set) var subject: String = ""
    public private(set) var serverName: String = ""

    public var draft: String = ""

    /// Shell-style history of messages sent from this composer. In-memory
    /// and per-scope (each `ChatViewModel` owns its own). Drives ↑/↓
    /// recall in the input field and the recent-messages menu.
    public private(set) var inputHistory = InputHistory()

    /// `nil` for public chat, otherwise a private room.
    public let chatScope: ChatID?

    /// Persisted transcript scroll intent. Lives on the (hoisted) VM so it
    /// survives the `SelectableTranscript` teardown a feature switch causes.
    public let transcriptScroll = TranscriptScrollAnchor()

    private let events: AsyncStream<HotlineEvent>
    private let sendChat: @Sendable (String, ChatID?, Bool) async throws -> Void
    private let changeSubject: @Sendable (ChatID, String) async throws -> Void
    private let resolveServerName: @Sendable () async -> String
    private let currentRoster: @Sendable () async -> [User]
    /// Reads the connection's recorded public topic. Used at start so a
    /// topic pushed BEFORE this VM began observing (e.g. login-time push)
    /// still shows. Returns "" when no topic is set.
    private let resolvePublicSubject: @Sendable () async -> String

    /// Sockets we've already seen. Seeded from the live roster on
    /// `observe()` so existing users aren't reported as fresh joins.
    private var seenSockets: Set<UInt16> = []
    /// socket → last known nickname; lets us render "Erika left" when
    /// the server only tells us the socket id on disconnect.
    private var nicknameCache: [UInt16: String] = [:]

    private var observationTask: Task<Void, Never>?

    /// Optional pre-fetched roster set by the host before `start()`. When
    /// non-nil, `observe()` uses it instead of issuing its own TX 300 —
    /// avoids the duplicate fetch when another VM on the same connection
    /// (e.g. `UserListViewModel`) is already fetching the same data.
    private var pendingRosterSeed: [User]?

    public init(
        events: AsyncStream<HotlineEvent>,
        sendChat: @escaping @Sendable (String, ChatID?, Bool) async throws -> Void,
        changeSubject: @escaping @Sendable (ChatID, String) async throws -> Void = { _, _ in },
        resolveServerName: @escaping @Sendable () async -> String = { "" },
        currentRoster: @escaping @Sendable () async -> [User] = { [] },
        resolvePublicSubject: @escaping @Sendable () async -> String = { "" },
        chatScope: ChatID? = nil
    ) {
        self.events = events
        self.sendChat = sendChat
        self.changeSubject = changeSubject
        self.resolveServerName = resolveServerName
        self.currentRoster = currentRoster
        self.resolvePublicSubject = resolvePublicSubject
        self.chatScope = chatScope
    }

    public convenience init(client: any HotlineClient, chatScope: ChatID? = nil) {
        self.init(
            events: client.events,
            sendChat: { [client] message, chat, isAction in
                try await client.sendChat(message, in: chat, isAction: isAction)
            },
            changeSubject: { [client] chat, subject in
                try await client.changeChatSubject(subject, in: chat)
            },
            resolveServerName: { [client] in
                // Bookmark name when set; address otherwise. Ad-hoc
                // `hotline://` connections have an empty `name`, and a
                // blank chat header doesn't help the user tell windows
                // apart.
                let info = await client.connectionInfo
                return info.settings.name.isEmpty ? info.settings.address : info.settings.name
            },
            currentRoster: { [client] in
                (try? await client.fetchUserList()) ?? []
            },
            resolvePublicSubject: { [client] in
                await client.connectionInfo.publicChatSubject
            },
            chatScope: chatScope
        )
    }

    /// Long-running observation. Designed for SwiftUI's
    /// `.task { await viewModel.observe() }` so cancellation propagates
    /// when the view disappears.
    public func observe() async {
        serverName = await resolveServerName()
        // Cover the login-time topic push that may have arrived before
        // this VM began observing.
        if chatScope == nil {
            let topic = await resolvePublicSubject()
            if !topic.isEmpty { subject = topic }
        }
        // Prefer a host-supplied pre-fetch over an independent fetchUserList
        // round-trip — see `seed(initialRoster:)`.
        let initialRoster: [User]
        if let preFetched = pendingRosterSeed {
            initialRoster = preFetched
            pendingRosterSeed = nil
        } else {
            initialRoster = await currentRoster()
        }
        for user in initialRoster {
            seenSockets.insert(user.socket)
            nicknameCache[user.socket] = user.nickname
        }

        for await event in events {
            switch event {
            case let .chatReceived(chat, message, isAction) where chat == chatScope:
                lines.append(Line(rawMessage: message, isAction: isAction))
            // Private rooms match their own ChatID; public chat (scope
            // nil) also accepts a Chat-ID-0 subject — that's how a
            // Heidrun server pushes the public topic (TX 119).
            case let .privateChatSubjectChanged(chat, newSubject)
                where chat == chatScope || (chatScope == nil && chat.rawValue == 0):
                subject = newSubject
            case let .userChanged(user):
                handleUserChanged(user)
            case let .userLeft(socket):
                handleUserLeft(socket: socket)
            default:
                break
            }
        }
    }

    /// First sight of a socket emits a system "joined" line; subsequent
    /// updates just refresh the nickname cache so the eventual `.userLeft`
    /// carries the right name. Only emits in public chat — private rooms
    /// have their own join events.
    private func handleUserChanged(_ user: User) {
        nicknameCache[user.socket] = user.nickname
        guard chatScope == nil else { return }
        if !seenSockets.contains(user.socket) {
            seenSockets.insert(user.socket)
            lines.append(
                Line(
                    sender: nil,
                    body: "\(user.nickname) entered",
                    isSystem: true
                )
            )
        }
    }

    private func handleUserLeft(socket: UInt16) {
        let name = nicknameCache[socket] ?? "Someone"
        nicknameCache[socket] = nil
        seenSockets.remove(socket)
        guard chatScope == nil else { return }
        lines.append(
            Line(
                sender: nil,
                body: "\(name) left",
                isSystem: true
            )
        )
    }

    /// Start `observe()` in a managed Task. Use when the VM outlives the
    /// chat view (so history doesn't restart on module switches).
    /// Idempotent.
    public func start() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self] in
            await self?.observe()
        }
    }

    /// Hand the VM a roster the host already fetched. Must be called
    /// before `start()` to take effect.
    public func seed(initialRoster: [User]) {
        pendingRosterSeed = initialRoster
    }

    public func cancel() {
        observationTask?.cancel()
        observationTask = nil
    }

    /// Wipe the visible transcript and leave a single muted trace.
    /// Local-only — does not send anything to the server.
    public func clearLines() {
        lines = [
            Line(sender: nil, body: "— Chat cleared —", isSystem: true)
        ]
    }

    /// Send the draft. Whitespace-only is a no-op so accidental Returns
    /// don't generate empty messages. Recognises `/clear` (exact,
    /// trimmed, case-insensitive) as a client-side wipe — never
    /// forwarded to the server.
    public func sendDraft() async throws {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.caseInsensitiveCompare("/clear") == .orderedSame {
            clearLines()
            draft = ""
            return
        }
        guard !text.isEmpty else { return }
        // Sending your own line re-pins to the bottom even if you'd
        // scrolled up reading history — the echo arrives via the event
        // stream and this intent makes that update scroll into view.
        transcriptScroll.followsBottom = true
        try await sendChat(text, chatScope, false)
        if Self.inputHistoryEnabled {
            inputHistory.record(text)
        }
        draft = ""
    }

    // MARK: - Input history

    /// Mirrors `Heidrun/App/AppStorageKeys.swift` —
    /// `chatInputHistoryEnabled` — kept as a literal so HeidrunChat
    /// doesn't depend on the app target. Rename in both places together.
    private static let inputHistoryEnabledKey = "Heidrun.chatInputHistoryEnabled"

    /// Whether the user has the in-memory recall feature enabled (default
    /// on). Read live so a Settings toggle takes effect immediately.
    private static var inputHistoryEnabled: Bool {
        UserDefaults.standard.object(forKey: inputHistoryEnabledKey) as? Bool ?? true
    }

    /// Wipe the in-memory history — used when the user turns the feature
    /// off in Settings.
    public func clearInputHistory() {
        inputHistory = InputHistory()
    }

    /// Most-recently-sent messages, newest first — for the recent menu.
    public var recentMessages: [String] { inputHistory.recent }

    /// ↑ recall: load the previous (older) sent message into the draft.
    /// Returns the recalled text for the input field, or `nil` to leave
    /// the field unchanged.
    public func recallPreviousDraft() -> String? {
        guard let recalled = inputHistory.recallPrevious(currentDraft: draft) else { return nil }
        draft = recalled
        return recalled
    }

    /// ↓ recall: load the next (newer) sent message, or restore the live
    /// draft once past the newest entry. `nil` leaves the field unchanged.
    public func recallNextDraft() -> String? {
        guard let recalled = inputHistory.recallNext() else { return nil }
        draft = recalled
        return recalled
    }

    /// End any in-progress ↑/↓ navigation (called when the user edits).
    public func resetHistoryNavigation() {
        inputHistory.resetNavigation()
    }

    /// Drop a recent message into the draft to edit/resend.
    public func useRecent(_ message: String) {
        draft = message
        inputHistory.resetNavigation()
    }

    /// No-op for the public scope — vanilla Hotline servers don't accept
    /// it there.
    public func setSubject(_ newSubject: String) async throws {
        guard let scope = chatScope else { return }
        try await changeSubject(scope, newSubject)
        subject = newSubject
    }
}
