import Foundation
import Observation
import HeidrunCore
import HeidrunBookmarks

/// Re-read on every decision (no caching) so a Settings toggle takes
/// effect on the next disconnect without wiring notifications.
struct AutoReconnectGlobalSettings: Sendable {
    var isEnabled: Bool
    var maxAttempts: Int
    var delaySeconds: Int

    /// Clamps to safe bounds so a bad `defaults`-edited plist can't
    /// break the runtime.
    static func live(defaults: UserDefaults = .standard) -> AutoReconnectGlobalSettings {
        AutoReconnectGlobalSettings(
            isEnabled: defaults.bool(forKey: AppStorageKeys.autoReconnectEnabled),
            maxAttempts: clampedMaxAttempts(
                defaults.object(forKey: AppStorageKeys.autoReconnectMaxAttempts) as? Int ?? 3
            ),
            delaySeconds: clampedDelaySeconds(
                defaults.object(forKey: AppStorageKeys.autoReconnectDelaySeconds) as? Int ?? 5
            )
        )
    }

    static func clampedMaxAttempts(_ value: Int) -> Int {
        max(1, min(20, value))
    }

    static func clampedDelaySeconds(_ value: Int) -> Int {
        max(1, min(120, value))
    }
}

/// Pure policy: decides whether an unexpected disconnect should retry,
/// schedules the retry, counts attempts. Owned by `HostState`; does not
/// open sockets itself.
@MainActor
@Observable
final class AutoReconnectCoordinator {

    private(set) var attempt: Int = 0

    /// Snapshotted at retry-schedule time so the UI's "attempt N of M"
    /// stays stable even if the user edits the global setting mid-cycle.
    private(set) var maxAttempts: Int = 0

    private let settingsProvider: @MainActor () -> AutoReconnectGlobalSettings
    private let bookmarkLookup: @MainActor (ConnectionSettings) -> Bookmark?
    private let sleep: @Sendable (Duration) async -> Void

    init(
        settingsProvider: @escaping @MainActor () -> AutoReconnectGlobalSettings = {
            AutoReconnectGlobalSettings.live()
        },
        bookmarkLookup: @escaping @MainActor (ConnectionSettings) -> Bookmark? = { settings in
            BookmarkRegistry.shared.bookmark(matching: settings)
        },
        sleep: @escaping @Sendable (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.settingsProvider = settingsProvider
        self.bookmarkLookup = bookmarkLookup
        self.sleep = sleep
    }

    /// Pure decision (no mutation). Returns `false` when bookmark =
    /// `.alwaysOff`, global toggle is off (without bookmark `.alwaysOn`),
    /// reason carries the `HotlineError` "server error" prefix (kick /
    /// protocol — retry is pointless), or the counter is at max.
    func shouldAutoReconnect(reason: String?, settings: ConnectionSettings) -> Bool {
        if let reason, reason.contains("server error") {
            return false
        }

        // Per-bookmark override wins over the global toggle.
        let global = settingsProvider()
        if let mark = bookmarkLookup(settings) {
            switch mark.autoReconnect {
            case .alwaysOn:
                break  // proceed to counter check
            case .alwaysOff:
                return false
            case .inherit:
                if !global.isEnabled { return false }
            }
        } else {
            if !global.isEnabled { return false }
        }

        // Counter cap.
        return attempt < global.maxAttempts
    }

    private var pendingRetry: Task<Void, Never>?

    /// No-op when counter is at max. Latest Task is held in
    /// `pendingRetry` so `cancel()` / `reset()` can stop it.
    func scheduleRetry(perform retry: @escaping @MainActor () -> Void) {
        let global = settingsProvider()
        guard attempt < global.maxAttempts else { return }
        attempt += 1
        maxAttempts = global.maxAttempts

        let delay = Duration.seconds(global.delaySeconds)
        let sleepFunction = sleep
        // Deliberately NOT cancelling a prior `pendingRetry` — in real
        // wiring two pending Tasks can't coexist (watcher returns after
        // one event; success goes through `reset()`). Cancelling would
        // also break the "3 synchronous scheduleRetry calls produce
        // exactly maxAttempts=2 invocations" test.
        pendingRetry = Task { @MainActor [weak self] in
            await sleepFunction(delay)
            guard let self, !Task.isCancelled else { return }
            self.pendingRetry = nil
            retry()
        }
    }

    /// Called on successful `.connected` and any user-initiated reconnect.
    func reset() {
        pendingRetry?.cancel()
        pendingRetry = nil
        attempt = 0
        maxAttempts = 0
    }

    /// Stop further attempts without zeroing the counter (telemetry).
    func cancel() {
        pendingRetry?.cancel()
        pendingRetry = nil
    }

    var isReconnecting: Bool { attempt > 0 }
}
