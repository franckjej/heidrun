import AppKit
import HeidrunUI

/// AppKit lifecycle hooks SwiftUI's `App` protocol can't express on its own:
/// activation policy, DocumentGroup cold-launch behaviour, and the
/// confirm-before-quit + session-snapshot flow at terminate.
final class HeidrunAppDelegate: NSObject, NSApplicationDelegate {
    /// `true` once `applicationShouldTerminate` has accepted the quit. Read by
    /// every host window's `onDisappear` so SwiftUI's during-quit teardown
    /// doesn't `disconnect()` live handles before `applicationWillTerminate`
    /// can snapshot them.
    nonisolated(unsafe) static var isTerminating = false

    /// Pre-empt SwiftUI's DocumentGroup cold-launch Open panel. Must run here
    /// (not in `didFinishLaunching`) to land before AppKit shows the panel.
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSDocumentController.shared.newDocument(nil)
        }
    }

    /// Strip AppKit's auto-injected File → Open Recent every menu rebuild.
    /// Our File → Recent Servers is the canonical list; without this scrub
    /// both appear side-by-side.
    func applicationWillUpdate(_ notification: Notification) {
        DispatchQueue.main.async {
            if let menu = NSApplication.shared.mainMenu?.item(at: 1) {
                if let file = menu.submenu?.items.first(where: {["Open Recent", "NSMenuItem"].contains($0.title)}), file.isKind(of: NSMenuItem.self) {
                    FileHandle.standardError.write(Data("\(file)".utf8))
                    menu.submenu?.removeItem(file)
                }
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
        FileHandle.standardError.write(Data("[HeidrunApp] launched\n".utf8))
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate()
        MainActor.assumeIsolated {
            NotificationCenterService.shared.install()
        }
    }

    /// Stay alive when the last window closes — Cmd+Q is the only exit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Dock-icon click with no visible windows: spawn a fresh untitled doc
    /// instead of letting AppKit pop the Open panel.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows: Bool
    ) -> Bool {
        guard !hasVisibleWindows else { return true }
        MainActor.assumeIsolated {
            NSDocumentController.shared.newDocument(nil)
        }
        return false
    }

    /// Tell AppKit to open an untitled doc on cold launch instead of the
    /// macOS Open panel DocumentGroup defaults to.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        MainActor.assumeIsolated {
            do {
                _ = try NSDocumentController.shared.openUntitledDocumentAndDisplay(true)
                return true
            } catch {
                return false
            }
        }
    }

    /// Prompt before quitting if any connection is live. Once accepted, the
    /// `isTerminating` flag tells every window's `onDisappear` to skip its
    /// own disconnect so `applicationWillTerminate` can snapshot the still-
    /// live handles.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let liveCount = MainActor.assumeIsolated {
            ActiveConnections.shared.connections.filter(\.isLive).count
        }
        let enabled = AppDataEnvironment.defaults.object(
            forKey: AppStorageKeys.confirmBeforeDisconnect
        ) as? Bool ?? true

        guard DisconnectConfirmation.shouldConfirmQuit(
            enabled: enabled,
            hasLiveConnections: liveCount > 0
        ) else {
            Self.isTerminating = true
            return .terminateNow
        }

        let confirmed = MainActor.assumeIsolated {
            DisconnectConfirmationAlert.confirmQuit(liveConnectionCount: liveCount)
        }
        guard confirmed else { return .terminateCancel }
        Self.isTerminating = true
        return .terminateNow
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MainActor.assumeIsolated {
            BadgeCounter.shared.reset()
        }
    }

    /// Snapshot live connections for next-launch restoration. Only
    /// `.connected` handles are saved (a `.failed` tombstone would just re-
    /// fail on every relaunch). Skipped under the test bundle so fake fixture
    /// connections don't pollute the user's real snapshot.
    func applicationWillTerminate(_ notification: Notification) {
        guard !TestEnvironment.isRunningUnderTests else { return }
        MainActor.assumeIsolated {
            let shouldReopen = (AppDataEnvironment.defaults.object(
                forKey: AppStorageKeys.reopenConnectionsOnLaunch
            ) as? Bool) ?? true
            guard shouldReopen else {
                SessionRestorationStore(defaults: AppDataEnvironment.defaults).clear()
                return
            }
            let liveSettings = ActiveConnections.shared.connections
                .filter { $0.isLive }
                .map { $0.settings }
            SessionRestorationStore(defaults: AppDataEnvironment.defaults).save(liveSettings)
        }
    }
}
