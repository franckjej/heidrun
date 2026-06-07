import Foundation
import Observation
import HeidrunCore

/// Live user-roster view model owned by the host window. Subscribes to the
/// client's event stream, applies user-list deltas, and exposes a couple of
/// row-action wrappers (`sendIM`, `requestInfo`).
@Observable
@MainActor
public final class UserListViewModel {
    public private(set) var users: [User] = []
    public private(set) var loadError: String?

    private let client: any HotlineClient
    private let eventStream: AsyncStream<HotlineEvent>
    private var eventTask: Task<Void, Never>?

    public init(client: any HotlineClient) {
        self.client = client
        // Subscribe at INIT, not in start(). The host creates this VM, then
        // snapshots the roster and runs several awaits (sound, notifications,
        // banner) before calling start(). Subscribing only in start() left a
        // window where a peer who joined mid-sequence was lost to the roster
        // — their `userChanged` broadcast landed before we subscribed — even
        // though ChatViewModel (which subscribes at init) showed them
        // "entered". That was the auto-reconnect desync: on a server
        // redeploy several clients reconnect inside that window. Capturing
        // the stream here closes it; events buffer (EventBroadcaster.
        // makeStream is unbounded) until start() drains them on top of the
        // seeded roster.
        self.eventStream = client.events
    }

    public func start(initialRoster: [User]? = nil) async {
        if let initialRoster {
            // Host already fetched the roster (e.g. ConnectionHandle
            // sharing it with ChatViewModel). Skip the redundant
            // round-trip — caller is responsible for accuracy.
            users = initialRoster
            loadError = nil
        } else {
            do {
                users = try await client.fetchUserList()
                loadError = nil
            } catch {
                loadError = String(describing: error)
            }
        }
        if eventTask == nil {
            let stream = eventStream
            eventTask = Task { [weak self] in
                for await event in stream {
                    self?.apply(event: event)
                }
            }
        }
    }

    public func cancel() {
        eventTask?.cancel()
        eventTask = nil
    }

    public func sendIM(to socket: UInt16, body: String) async throws {
        try await client.sendPrivateMessage(body, to: socket)
    }

    public func requestInfo(for socket: UInt16) async throws -> UserInfo {
        try await client.fetchUserInfo(socket: socket)
    }

    /// Open a private chat with `socket`. Returns the new chat's id so the
    /// host can spin up a chat surface for it.
    public func startPrivateChat(with socket: UInt16) async throws -> ChatID {
        try await client.createPrivateChat(with: socket)
    }

    /// Disconnect (kick) `socket`. Passes `ban: false` so this is a
    /// soft-kick without adding to the server's ban list.
    public func disconnect(socket: UInt16) async throws {
        try await client.kick(socket: socket, ban: false)
    }

    /// Mirror a successful TX 304 (changeNickname) into the local roster
    /// for our own socket. HeidrunServer broadcasts `userChanged` with
    /// `excluding=sender`, so without this manual apply the sender's own
    /// row would never reflect their new icon / nickname.
    public func applyLocalSelfChange(
        socket: UInt16, icon: UInt16, nickname: String, emoji: String?
    ) {
        if let index = users.firstIndex(where: { $0.socket == socket }) {
            users[index].icon = icon
            users[index].nickname = nickname
            users[index].emoji = emoji
        }
    }

    private func apply(event: HotlineEvent) {
        switch event {
        case .userListReceived(let list):
            // Every .userListReceived here is an UNSOLICITED server push —
            // the explicit roster fetch uses the request/reply path, not the
            // event stream. An empty one is always spurious (e.g. an HXD
            // privileges TX 354, or a push whose entries all failed to
            // decode) and must never wipe a populated roster. Defense-in-
            // depth behind the HeidrunCore engine fix that stops privs-only
            // 354 from decoding to an empty roster in the first place.
            guard !list.isEmpty else {
                break
            }
            users = list
            loadError = nil
        case .userChanged(let user):
            if let idx = users.firstIndex(where: { $0.socket == user.socket }) {
                users[idx] = user
            } else {
                users.append(user)
            }
        case .userLeft(let socket):
            users.removeAll { $0.socket == socket }
        default:
            break
        }
    }
}
