import AppKit
import UserNotifications

/// Tracks unread private-message and chat-invite count so the Dock icon
/// carries a badge while Heidrun isn't the frontmost app. Mirrors Mail's
/// behavior: increments fire only when the app isn't active, and the
/// counter resets to zero when the user activates Heidrun (any window
/// becomes key, app comes back to the front, etc.).
///
/// Owned by `NotificationCenterService` (which calls `increment(for:)`
/// before adding a notification request) and the app delegate (which
/// calls `reset()` from `applicationDidBecomeActive`).
@MainActor
final class BadgeCounter {
    static let shared = BadgeCounter()

    private(set) var unreadCount: Int = 0
    private let center: UNUserNotificationCenter
    private let isAppActive: @MainActor () -> Bool

    init(
        center: UNUserNotificationCenter = .current(),
        isAppActive: @escaping @MainActor () -> Bool = { NSApp.isActive }
    ) {
        self.center = center
        self.isAppActive = isAppActive
    }

    /// Increment if `kind` represents an unread-worthy event AND Heidrun
    /// is currently not the active application. The active-check skip
    /// keeps the badge silent while the user is already reading; a
    /// new private message that arrives while the user is *in* Heidrun
    /// doesn't add to the unread pile.
    func increment(for kind: NotificationCenterService.Kind) {
        guard countsTowardBadge(kind) else { return }
        guard !isAppActive() else { return }
        unreadCount += 1
        apply()
    }

    /// Reset the badge. Called from `applicationDidBecomeActive` so the
    /// Dock icon clears the moment the user comes back to Heidrun.
    func reset() {
        guard unreadCount > 0 else { return }
        unreadCount = 0
        apply()
    }

    /// Which notification kinds contribute to the badge. Connect/
    /// disconnect/transfer/news fire banners but don't represent an
    /// unread item waiting for the user, so they're excluded.
    private func countsTowardBadge(_ kind: NotificationCenterService.Kind) -> Bool {
        switch kind {
        case .privateMessage, .chatInvite:
            return true
        case .connected, .disconnected, .transferFinished, .newsPosted, .broadcast:
            return false
        }
    }

    /// Push the current count to the system. `setBadgeCount(_:)` is the
    /// macOS 14+ API that updates both the Dock icon and the value the
    /// UserNotifications framework reports back to system surfaces.
    private func apply() {
        let snapshot = unreadCount
        Task { [center] in
            try? await center.setBadgeCount(snapshot)
        }
    }
}
