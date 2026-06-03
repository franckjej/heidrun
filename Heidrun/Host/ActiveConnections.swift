import Foundation
import Observation
import HeidrunCore

/// App-wide registry of live `ConnectionHandle` instances — one per host
/// window. TaskManager iterates this; tests can pass their own instance
/// via `HostState.init(connections:)`.
@MainActor
@Observable
final class ActiveConnections {
    static let shared = ActiveConnections()

    private(set) var connections: [ConnectionHandle] = []

    func register(_ handle: ConnectionHandle) {
        guard !connections.contains(where: { $0.id == handle.id }) else { return }
        connections.append(handle)
        persistLiveSnapshot()
    }

    func deregister(_ id: ConnectionHandle.ID) {
        connections.removeAll { $0.id == id }
        persistLiveSnapshot()
    }

    /// Automatic on register/deregister; call explicitly after a change
    /// that flipped `isLive` without adding/removing (e.g.
    /// `markDisconnected`). Eager persistence so a force-quit between
    /// disconnect and quit doesn't leave a disconnected server on the
    /// next-launch list.
    func persistLiveSnapshot() {
        let shouldReopen = (UserDefaults.standard.object(
            forKey: AppStorageKeys.reopenConnectionsOnLaunch
        ) as? Bool) ?? true
        guard shouldReopen else {
            SessionRestorationStore().clear()
            return
        }
        let liveSettings = connections
            .filter { $0.isLive }
            .map { $0.settings }
        SessionRestorationStore().save(liveSettings)
    }

    /// Fans TX 304 to every live connection. Reads each server's current
    /// nickname-for-us from the roster (keyed by our own socket) so we
    /// don't revert an agreement-sheet rename; falls back to
    /// `settings.nickname` when the roster hasn't observed our login.
    /// Per-connection errors are logged but don't abort the fan-out.
    func broadcastSelfIdentity(icon iconID: UInt16, emoji: String?) {
        let liveCount = connections.lazy.filter(\.isLive).count
        FileHandle.standardError.write(Data(
            "[ActiveConnections] broadcastSelfIdentity(icon: \(iconID), emoji: \(emoji ?? "nil")) — \(liveCount) live connection(s)\n".utf8
        ))
        for handle in connections where handle.isLive {
            let client = handle.client
            let userListVM = handle.userListVM
            let fallbackNickname = handle.settings.nickname.isEmpty ? NSFullUserName() : handle.settings.nickname
            let displayName = handle.displayName
            Task { @MainActor in
                let ownSocket = await client.connectionInfo.connectionSocket
                let liveNickname = userListVM.users.first(where: { $0.socket == ownSocket })?.nickname
                let nickname = liveNickname ?? fallbackNickname
                FileHandle.standardError.write(Data(
                    "[ActiveConnections] pushing identity to \(displayName) as \"\(nickname)\" (socket \(ownSocket))\n".utf8
                ))
                do {
                    try await client.changeNickname(nickname, icon: iconID, emoji: emoji, persist: false)
                    // Server excludes the sender from its userChanged broadcast,
                    // so mirror the change into our own roster manually.
                    userListVM.applyLocalSelfChange(
                        socket: ownSocket, icon: iconID, nickname: nickname, emoji: emoji
                    )
                    // Sync stored settings so the on-quit snapshot
                    // carries the current identity, not the connect-time
                    // values — else relaunch reopens with stale identity.
                    handle.settings.nickname = nickname
                    handle.settings.icon = iconID
                    handle.settings.emoji = emoji
                    self.persistLiveSnapshot()
                } catch {
                    FileHandle.standardError.write(Data(
                        "[ActiveConnections] identity push failed for \(displayName): \(error)\n".utf8
                    ))
                }
            }
        }
    }
}
