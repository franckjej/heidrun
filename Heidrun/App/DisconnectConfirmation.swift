import AppKit

/// Pure gating logic for the "you're about to disconnect" prompts. Kept
/// free of AppKit state so the decision matrix is unit-testable; the
/// `NSAlert` presentation lives in `DisconnectConfirmationAlert` below.
enum DisconnectConfirmation {
    /// Prompt before closing a window? Only when the toggle is on and the
    /// window holds a live connection. A disconnected window (showing the
    /// connect form) closes without a prompt.
    static func shouldConfirmWindowClose(enabled: Bool, isConnected: Bool) -> Bool {
        enabled && isConnected
    }

    /// Prompt before quitting? Only when the toggle is on and at least one
    /// connection is still live.
    static func shouldConfirmQuit(enabled: Bool, hasLiveConnections: Bool) -> Bool {
        enabled && hasLiveConnections
    }
}

/// Thin AppKit shell that builds and runs the confirmation alerts. Both
/// helpers return `true` when the user chose to proceed (close / quit).
///
/// Key bindings (handled in `runConfirm` below):
/// - **Return / numpad Enter** → destructive action (Quit / Disconnect).
/// - **Escape** → Cancel.
///
/// This is a deliberate flip from the Apple HIG default ("Return should
/// pick the safer choice for a destructive alert") — the prompt only
/// appears in direct response to a user-initiated Cmd+Q / Cmd+W, so a
/// one-keystroke confirm matches the user's already-expressed intent
/// rather than introducing a second hoop. The destructive button keeps
/// its red-filled bezel (`hasDestructiveAction = true`); Return is
/// wired via a local `NSEvent` monitor because NSAlert refuses to
/// promote a destructive button to default on macOS Sonoma+.
@MainActor
enum DisconnectConfirmationAlert {
    /// Confirm closing one connected window. `wouldQuitApp` only changes
    /// the wording — when closing this window would also terminate the
    /// app (it's the last main window), the prompt talks about quitting.
    static func confirmWindowClose(serverName: String, wouldQuitApp: Bool) -> Bool {
        let alert = NSAlert()
        if wouldQuitApp {
            alert.messageText = String(localized: "Quit Heidrun?")
            alert.informativeText = String(
                localized: "You're still connected to \(serverName). Quitting will disconnect you."
            )
        } else {
            alert.messageText = String(localized: "Disconnect from \(serverName)?")
            alert.informativeText = String(
                localized: "Closing this window will end your session on \(serverName)."
            )
        }
        let actionTitle = wouldQuitApp
            ? String(localized: "Quit")
            : String(localized: "Disconnect")
        return runConfirm(alert, actionTitle: actionTitle)
    }

    /// Confirm quitting while `liveConnectionCount` connections are live.
    static func confirmQuit(liveConnectionCount: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Quit Heidrun?")
        alert.informativeText = String(
            localized: "You're connected to \(liveConnectionCount) server(s). Quitting will disconnect from all of them."
        )
        return runConfirm(alert, actionTitle: String(localized: "Quit"))
    }

    /// Shared button wiring. Adds Cancel first + action button second
    /// (so the modal-result enum stays `.alertSecondButtonReturn` for
    /// "proceed"). Key bindings:
    ///   - Return / numpad Enter → action button.
    ///   - Escape → Cancel.
    ///
    /// Why the local event monitor: macOS Sonoma / Tahoe NSAlert
    /// SUPPRESSES the default-button (pulsing-blue, Return-bound)
    /// affordance whenever any button has `hasDestructiveAction =
    /// true`. So neither button gets the default-action key. We want
    /// BOTH the red-filled destructive visual AND a working Return
    /// binding — installing a local NSEvent monitor that catches
    /// Return during the modal and calls `actionButton.performClick`
    /// gives us both: AppKit keeps painting the destructive bezel,
    /// we own the key-equivalence ourselves.
    private static func runConfirm(_ alert: NSAlert, actionTitle: String) -> Bool {
        let cancelButton = alert.addButton(withTitle: String(localized: "Cancel"))
        let actionButton = alert.addButton(withTitle: actionTitle)
        actionButton.hasDestructiveAction = true
        // Explicit `""` on the action button (instead of leaving
        // AppKit's auto-`"\r"` on Cancel) makes the intent obvious:
        // no key drives either button via NSAlert's built-in path.
        // Return / Esc are both handled by the monitor + Cancel's
        // explicit Escape assignment below.
        cancelButton.keyEquivalent = "\u{1b}"
        actionButton.keyEquivalent = ""

        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 36 = Return, 76 = numpad Enter. Both confirm.
            if event.keyCode == 36 || event.keyCode == 76 {
                actionButton.performClick(nil)
                return nil  // swallow so AppKit doesn't double-fire
            }
            return event
        }
        defer {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        return alert.runModal() == .alertSecondButtonReturn
    }
}
