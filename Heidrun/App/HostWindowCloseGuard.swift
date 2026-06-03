import AppKit

/// `NSWindowDelegate` installed on each host window so a close that would
/// drop a live connection can be vetoed with a confirmation prompt. Lives
/// at the window level because SwiftUI's `onDisappear` runs
/// `state.disconnect()` before `applicationShouldTerminate` fires —
/// `windowShouldClose` is the only hook that sees the live connection in
/// time. Forwards every message it doesn't implement to the prior
/// (SwiftUI-installed) delegate.
@MainActor
final class HostWindowCloseGuard: NSObject, NSWindowDelegate {
    private weak var state: HostState?
    /// `nonisolated(unsafe)` because the Obj-C runtime calls
    /// `responds(to:)` / `forwardingTarget(for:)` from a nonisolated
    /// context. Set once in `install` on main before the delegate goes
    /// live, then only read on main from those callbacks — serialized.
    nonisolated(unsafe) private weak var priorDelegate: NSWindowDelegate?

    init(state: HostState) {
        self.state = state
        super.init()
    }

    /// Idempotent — `WindowAccessor` can fire more than once.
    func install(on window: NSWindow) {
        guard window.delegate !== self else { return }
        priorDelegate = window.delegate
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // A quit in progress owns the prompt — never double-ask.
        if HeidrunAppDelegate.isTerminating { return true }

        let enabled = AppDataEnvironment.defaults.object(
            forKey: AppStorageKeys.confirmBeforeDisconnect
        ) as? Bool ?? true

        guard let state,
              DisconnectConfirmation.shouldConfirmWindowClose(
                enabled: enabled,
                isConnected: state.isConnected
              )
        else {
            return true
        }

        // Since the DocumentGroup migration the app stays alive when the
        // last window closes (`applicationShouldTerminateAfter-
        // LastWindowClosed` returns false), so a window-close never
        // doubles as a quit. Quit wording is only reached via
        // `applicationShouldTerminate`.
        return DisconnectConfirmationAlert.confirmWindowClose(
            serverName: state.serverName,
            wouldQuitApp: false
        )
    }

    /// Tear the connection down at AppKit's `windowWillClose` instead of
    /// SwiftUI's `onDisappear` — DocumentGroup fires `onDisappear`
    /// inconsistently for user-initiated closes, which would leave the
    /// `ConnectionHandle` registered in `ActiveConnections` with
    /// `isLive == true` and Cmd+Q would then snapshot that ghost into
    /// the session-restoration store. Skipped during termination so
    /// `applicationWillTerminate` can snapshot still-live handles for
    /// next-launch restore.
    func windowWillClose(_ notification: Notification) {
        defer { forwardWindowWillClose(notification) }
        guard !HeidrunAppDelegate.isTerminating else { return }
        state?.disconnect()
    }

    private func forwardWindowWillClose(_ notification: Notification) {
        guard let priorDelegate,
              priorDelegate.responds(to: #selector(NSWindowDelegate.windowWillClose(_:))) else {
            return
        }
        priorDelegate.windowWillClose?(notification)
    }

    // MARK: - Delegate forwarding

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return priorDelegate?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if super.responds(to: aSelector) { return nil }
        return priorDelegate
    }
}
