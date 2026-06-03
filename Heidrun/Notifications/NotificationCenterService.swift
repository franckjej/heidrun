import Foundation
import AppKit
import HeidrunFiles
import UserNotifications

/// Stable identity of a connected host. Carried on every notification so
/// Notification Center can group per-server (`threadIdentifier`) and the
/// click handler can focus the right window. `id` mirrors
/// `ConnectionHandle.id.uuidString`.
struct HostIdentity: Sendable, Hashable {
    let id: String
    let displayName: String
}

/// Minimal seam so `NotificationCoordinator` (and its tests) can swap
/// the real service for a recording fake.
@MainActor
protocol NotificationPosting {
    func post(_ event: NotificationCenterService.Event, host: HostIdentity) async
}

/// App-wide entry point. Owns the `UNUserNotificationCenter` delegate,
/// the lazy authorization request, and the user-preference filter.
///
/// `install()` is called once from
/// `HeidrunAppDelegate.applicationDidFinishLaunching`.
@MainActor
final class NotificationCenterService: NSObject {
    static let shared = NotificationCenterService()

    enum Event: Sendable {
        case connected
        case disconnected(reason: String?)
        case privateMessage(senderName: String, body: String)
        case chatInvite(senderName: String, message: String?)
        case transferFinished(filename: String, direction: FilesViewModel.TransferDirection)
        case newsPosted(text: String)
        case broadcast(text: String)

        /// Raw-string-stable id for `userInfo` and the prefs filter.
        var kind: Kind {
            switch self {
            case .connected:
                return .connected
            case .disconnected:
                return .disconnected
            case .privateMessage:
                return .privateMessage
            case .chatInvite:
                return .chatInvite
            case .transferFinished:
                return .transferFinished
            case .newsPosted:
                return .newsPosted
            case .broadcast:
                return .broadcast
            }
        }
    }

    /// Raw values are persisted in `userInfo` — renames must update any
    /// notifications still in flight.
    enum Kind: String, Sendable, CaseIterable {
        case connected
        case disconnected
        case privateMessage
        case chatInvite
        case transferFinished
        case newsPosted
        case broadcast

        var preferenceKey: String {
            switch self {
            case .connected:
                return AppStorageKeys.notifyConnected
            case .disconnected:
                return AppStorageKeys.notifyDisconnected
            case .privateMessage:
                return AppStorageKeys.notifyPrivateMessage
            case .chatInvite:
                return AppStorageKeys.notifyChatInvite
            case .transferFinished:
                return AppStorageKeys.notifyTransferFinished
            case .newsPosted:
                return AppStorageKeys.notifyNewsPosted
            case .broadcast:
                return AppStorageKeys.notifyBroadcast
            }
        }
    }

    /// Lazy: we don't `requestAuthorization` at launch. The first
    /// `post(_:host:)` triggers the prompt; the result is cached.
    private enum AuthorizationState {
        case unknown
        case allowed
        case denied
    }

    private var authorization: AuthorizationState = .unknown
    private var authorizationTask: Task<Bool, Never>?
    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard
    ) {
        self.center = center
        self.defaults = defaults
        super.init()
    }

    func install() {
        center.delegate = self
    }

    /// Silent no-op when the global toggle is off, the per-event toggle
    /// is off, the user denied permission, or the system errors on `add`.
    func post(_ event: Event, host: HostIdentity) async {
        guard isEnabled(for: event.kind) else { return }
        guard await ensureAuthorized() else { return }

        // Tally first so the badge matches the count in Notification
        // Center.
        BadgeCounter.shared.increment(for: event.kind)

        let content = NotificationContent.makeContent(for: event, host: host)
        let request = UNNotificationRequest(
            identifier: NotificationContent.identifierPrefix + UUID().uuidString,
            content: content,
            trigger: nil
        )
        do {
            try await center.add(request)
        } catch {
            // Best-effort.
        }
    }

    /// Reads through to UNUserNotificationCenter, not the cached state —
    /// the user can toggle permission in System Settings while the app
    /// is running.
    func authorizationStatusForDisplay() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    private func isEnabled(for kind: Kind) -> Bool {
        guard isGloballyEnabled else { return false }
        return readBool(forKey: kind.preferenceKey, defaultValue: true)
    }

    private var isGloballyEnabled: Bool {
        readBool(forKey: AppStorageKeys.notificationsEnabled, defaultValue: true)
    }

    /// `UserDefaults.bool(forKey:)` returns `false` for missing keys
    /// but our defaults are `true` — read the underlying object.
    private func readBool(forKey key: String, defaultValue: Bool) -> Bool {
        if let stored = defaults.object(forKey: key) as? Bool {
            return stored
        }
        return defaultValue
    }

    /// Concurrent posts share the single in-flight request so we don't
    /// pop two prompts.
    private func ensureAuthorized() async -> Bool {
        switch authorization {
        case .allowed:
            return true
        case .denied:
            return false
        case .unknown:
            break
        }
        if let inFlight = authorizationTask {
            return await inFlight.value
        }
        let task = Task<Bool, Never> { [center] in
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge])) ?? false
            return granted
        }
        authorizationTask = task
        let granted = await task.value
        authorization = granted ? .allowed : .denied
        authorizationTask = nil
        return granted
    }
}

extension NotificationCenterService: NotificationPosting {}

extension NotificationCenterService: UNUserNotificationCenterDelegate {
    /// Always present the banner — Heidrun is multi-window, and the user
    /// could be on server A's Files window when a PM lands on server B.
    /// No sound (SoundCoordinator handles its own cue).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    /// Activate the app and front the originating host window. Per-
    /// feature focus (e.g. opening Messages on a PM click) is
    /// deliberately deferred.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let hostID = userInfo[NotificationContent.UserInfoKey.hostID] as? String
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            guard let hostID,
                  let handle = ActiveConnections.shared.connections
                    .first(where: { $0.id.uuidString == hostID }),
                  let window = handle.window
            else { return }
            window.makeKeyAndOrderFront(nil)
        }
    }
}
