import Foundation
import UserNotifications

/// Pure mapping from a domain notification event to the `UNMutableNotificationContent`
/// that the system actually displays. Kept free of `UNUserNotificationCenter` calls
/// so it stays trivially unit-testable — the service layer takes care of posting.
///
/// Each result carries:
/// - a `threadIdentifier` derived from the host so Notification Center stacks
///   per-server (Mail-style grouping).
/// - `userInfo` keys `hostID` and `eventKind` consumed by the click handler.
/// - no `sound`. Audio cues are owned by `SoundCoordinator`; doubling sounds
///   on every banner would be annoying.
enum NotificationContent {
    /// Identifier prefix shared by every Heidrun-posted request. Currently
    /// unused for filtering but lets a future "clear all Heidrun notifications"
    /// surface match against `request.identifier.hasPrefix(...)`.
    static let identifierPrefix = "heidrun.notification."

    /// User-info keys carried on every request. String-typed so the click
    /// handler decoder doesn't need a private cast helper.
    enum UserInfoKey {
        static let hostID = "hostID"
        static let eventKind = "eventKind"
    }

    /// Build the system content for `event` originating from `host`.
    /// `userListLookup` resolves a socket → nickname (returns `nil` if the
    /// roster hasn't seen the sender yet, which falls back to "user N").
    @MainActor
    static func makeContent(
        for event: NotificationCenterService.Event,
        host: HostIdentity
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.threadIdentifier = host.id
        content.userInfo = [
            UserInfoKey.hostID: host.id,
            UserInfoKey.eventKind: event.kind.rawValue
        ]

        switch event {
        case .connected:
            content.title = "Connected"
            content.body = host.displayName

        case let .disconnected(reason):
            content.title = "Disconnected"
            if let reason, !reason.isEmpty {
                content.body = "\(host.displayName) — \(reason)"
            } else {
                content.body = host.displayName
            }

        case let .privateMessage(senderName, body):
            content.title = senderName
            content.body = truncate(body, to: 120)
            content.subtitle = host.displayName

        case let .chatInvite(senderName, message):
            content.title = "Chat invitation from \(senderName)"
            content.body = (message.flatMap { truncate($0, to: 120) }) ?? "wants to chat"
            content.subtitle = host.displayName

        case let .transferFinished(filename, direction):
            content.title = (direction == .upload) ? "Upload complete" : "Download complete"
            content.body = filename
            content.subtitle = host.displayName

        case let .newsPosted(text):
            content.title = "News"
            content.body = truncate(text, to: 120)
            content.subtitle = host.displayName

        case let .broadcast(text):
            content.title = host.displayName
            content.subtitle = "Server broadcast"
            content.body = text
            content.threadIdentifier = "host.\(host.id).broadcast"
            // sound stays nil — SoundCoordinator already plays
            // .serverMessage for the same event.
        }

        return content
    }

    /// Trim `text` to at most `limit` user-perceived characters, appending
    /// a horizontal ellipsis when truncated. Operates on `String` (not
    /// `String.UnicodeScalarView`) so multi-scalar emoji stay intact.
    static func truncate(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let prefix = text.prefix(limit - 1)
        return "\(prefix)…"
    }
}
