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

    /// Default delay before an unanswered quit prompt quits anyway.
    static let defaultQuitAutoConfirmSeconds = 30

    /// Choices offered in Settings; 0 = never auto-quit.
    static let quitAutoConfirmChoices = [0, 15, 30, 60, 120]

    /// Quit reasons macOS attaches to the quit Apple Event on logout,
    /// restart and shutdown ('logo', 'rlgo', 'rest', 'shut', 'rrst', 'rsdn').
    static let systemSessionEndQuitReasons: Set<OSType> = [
        OSType(kAELogOut), OSType(kAEReallyLogOut),
        OSType(kAERestart), OSType(kAEShutDown),
        OSType(kAEShowRestartDialog), OSType(kAEShowShutdownDialog)
    ]

    /// `true` when the quit was sent by a system logout / restart /
    /// shutdown — those skip the prompt so they're never blocked.
    static func isSystemSessionEnd(quitReason: OSType?) -> Bool {
        guard let quitReason else { return false }
        return systemSessionEndQuitReasons.contains(quitReason)
    }

    /// Reason code of the quit Apple Event currently being handled, if any.
    static func currentQuitReason() -> OSType? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == OSType(kCoreEventClass),
              event.eventID == OSType(kAEQuitApplication) else { return nil }
        return event.attributeDescriptor(forKeyword: OSType(kAEQuitReason))?.enumCodeValue
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
    /// `autoConfirmSeconds` > 0 quits after that many seconds unanswered.
    static func confirmQuit(liveConnectionCount: Int, autoConfirmSeconds: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Quit Heidrun?")
        alert.informativeText = String(
            localized: "You're connected to \(liveConnectionCount) server(s). Quitting will disconnect from all of them."
        )
        return runConfirm(
            alert,
            actionTitle: String(localized: "Quit"),
            autoConfirmAfter: autoConfirmSeconds > 0 ? autoConfirmSeconds : nil
        )
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
    ///
    /// `autoConfirmAfter` (seconds) shows a countdown line below the
    /// message and clicks the action button when it reaches zero.
    private static func runConfirm(
        _ alert: NSAlert,
        actionTitle: String,
        autoConfirmAfter countdownSeconds: Int? = nil
    ) -> Bool {
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
        let countdownTimer = countdownSeconds.map { seconds in
            startCountdown(seconds: seconds, alert: alert, actionButton: actionButton)
        }
        defer {
            if let monitor { NSEvent.removeMonitor(monitor) }
            countdownTimer?.invalidate()
        }
        return alert.runModal() == .alertSecondButtonReturn
    }

    /// Adds a "Quitting automatically in 30 seconds…" line as the alert's
    /// accessory view, ticks it down once per second and clicks the action
    /// button at zero. The countdown lives outside the button because
    /// AppKit ignores custom title colors on destructive buttons. Scheduled
    /// in `.common` modes so it fires inside `runModal`'s modal run loop.
    private static func startCountdown(
        seconds: Int,
        alert: NSAlert,
        actionButton: NSButton
    ) -> Timer {
        let countdownLabel = NSTextField(labelWithString: countdownText(seconds: seconds))
        countdownLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        countdownLabel.textColor = .secondaryLabelColor
        // NSAlert centres a narrower accessory view, so stretch the label to
        // the message text's width to line it up leading with the text.
        countdownLabel.alignment = .natural
        countdownLabel.sizeToFit()
        alert.accessoryView = countdownLabel
        alert.layout()
        let messageTextWidth = alert.window.contentView
            .flatMap { textField(showing: alert.informativeText, in: $0) }?
            .frame.width
        if let messageTextWidth {
            countdownLabel.setFrameSize(NSSize(width: messageTextWidth, height: countdownLabel.frame.height))
            alert.layout()
        }

        let deadline = Date.now.addingTimeInterval(TimeInterval(seconds))
        let timer = Timer(timeInterval: 1, repeats: true) { timer in
            MainActor.assumeIsolated {
                let remaining = Int(deadline.timeIntervalSinceNow.rounded())
                if remaining <= 0 {
                    timer.invalidate()
                    actionButton.performClick(nil)
                } else {
                    countdownLabel.stringValue = countdownText(seconds: remaining)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private static func textField(showing text: String, in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.stringValue == text { return field }
        for subview in view.subviews {
            if let match = textField(showing: text, in: subview) { return match }
        }
        return nil
    }

    private static func countdownText(seconds: Int) -> String {
        let duration = Duration.seconds(seconds).formatted(.units(width: .wide))
        return String(localized: "Quitting automatically in \(duration)…")
    }
}
