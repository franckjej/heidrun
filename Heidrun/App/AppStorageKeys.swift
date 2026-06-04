import Foundation

/// Single source of truth for `@AppStorage` keys. Constants here prevent
/// typo drift between writer and reader.
enum AppStorageKeys {
    static let defaultNickname = "Heidrun.defaultNickname"
    static let defaultIconID = "Heidrun.defaultIconID"
    /// UTF-8 emoji (empty == none).
    static let defaultEmoji = "Heidrun.defaultEmoji"
    /// Local-only user-list banner stripe id (0 = none).
    static let defaultBannerID = "Heidrun.defaultBannerID"
    static let defaultPort = "Heidrun.defaultPort"
    static let downloadFolderBookmark = "Heidrun.downloadFolderBookmark"
    static let rememberRecents = "Heidrun.rememberRecents"

    /// Italic time-of-day before each chat line. Off by default.
    static let showChatTimestamps = "Heidrun.showChatTimestamps"

    /// "Erika entered" / "Erika left" system lines. On by default.
    static let showChatJoinLeave = "Heidrun.showChatJoinLeave"

    /// When off, an unexpected disconnect goes to `.failed` (unless a
    /// matching bookmark has `autoReconnect == .alwaysOn`). Default off.
    static let autoReconnectEnabled = "Heidrun.autoReconnectEnabled"

    /// Clamped 1...20. Default 3.
    static let autoReconnectMaxAttempts = "Heidrun.autoReconnectMaxAttempts"

    /// Clamped 1...120. Default 5.
    static let autoReconnectDelaySeconds = "Heidrun.autoReconnectDelaySeconds"

    /// Master toggle. Authorization is requested lazily on first post —
    /// flipping this on does NOT prompt by itself. Default on.
    static let notificationsEnabled = "Heidrun.notificationsEnabled"

    /// Per-event toggles. All default to `true`.
    static let notifyConnected = "Heidrun.notifyConnected"
    static let notifyDisconnected = "Heidrun.notifyDisconnected"
    static let notifyPrivateMessage = "Heidrun.notifyPrivateMessage"
    static let notifyChatInvite = "Heidrun.notifyChatInvite"
    static let notifyTransferFinished = "Heidrun.notifyTransferFinished"
    static let notifyNewsPosted = "Heidrun.notifyNewsPosted"
    static let notifyBroadcast = "Heidrun.notifyBroadcast"

    /// Bounce the dock when a private message arrives and the user
    /// can't already see it. Default on. Mirrored as a literal in
    /// `MessagesViewModel.dockBounceKey` so HeidrunMessages doesn't have
    /// to import the app target.
    static let dockBounceOnPrivateMessage = "Heidrun.dockBounceOnPrivateMessage"

    /// Show the unread-thread count on the dock icon. Default on.
    /// Mirrored as a literal in `MessagesViewModel.dockBadgeKey`.
    static let dockBadgeForUnreadMessages = "Heidrun.dockBadgeForUnreadMessages"

    /// JSON `[TrackerHost]`. Default-seeded with `hltracker.com:5498`.
    static let trackerHosts = "Heidrun.trackerHosts"

    /// Hidden power-user override:
    /// `defaults write org.tastybytes.heidrun Heidrun.trackerTimeoutSeconds <seconds>`.
    /// Absent or ≤ 0 → `TrackerTimeoutDefaults.fallbackSeconds` (20).
    static let trackerTimeoutSeconds = "Heidrun.trackerTimeoutSeconds"

    /// Snapshot live connections at quit, reopen them next launch.
    /// Default on.
    static let reopenConnectionsOnLaunch = "Heidrun.reopenConnectionsOnLaunch"

    /// JSON `[ConnectionSettings]` snapshot for `SessionRestorationStore`.
    /// Not exposed in Settings — managed by the app delegate.
    static let sessionRestoration = "Heidrun.sessionRestoration"

    /// Bind saved passwords to a `.userPresence` keychain ACL. In-memory
    /// session cache means each `(server, login)` only prompts once per
    /// app launch. Defaults to `false` so the headless test bundle (which
    /// uses this app target as host) doesn't bind saves to a UI prompt.
    static let useBiometricPasswordProtection = "Heidrun.useBiometricPasswordProtection"

    /// Confirm before any action that would drop a live connection (close
    /// window, Cmd+Q). Default on. Read via `AppDataEnvironment.defaults`
    /// so isolated runs honor their own suite.
    static let confirmBeforeDisconnect = "Heidrun.confirmBeforeDisconnect"

    /// Developer toggle: new connections attach a `PacketObserver` that
    /// funnels every wire transaction into `ProtocolConsoleStore`. Off by
    /// default — pure overhead when not debugging dialects.
    static let enableProtocolConsole = "Heidrun.enableProtocolConsole"

    /// `ContentSize.Preset` rawValue. Default `standard`. Mirrored as a
    /// literal in `HeidrunUI.ContentSizeReader.storageKey` so HeidrunUI
    /// doesn't have to import the app target.
    static let contentSize = "Heidrun.contentSize"
}
