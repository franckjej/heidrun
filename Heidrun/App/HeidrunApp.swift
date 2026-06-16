import SwiftUI
import os
import CommonTools
import HeidrunCore
import HeidrunUI
import HeidrunChat
import HeidrunMessages
import HeidrunNews
import HeidrunFiles
import HeidrunAdmin
import HeidrunBookmarks

private let bookmarksOpenLogger = Logger(
    subsystem: "org.tastybytes.heidrun",
    category: "BookmarksOpenURL"
)

/// macOS entry point. Each host window is a `HeidrunBookmarkDocument`
/// scene under `DocumentGroup`; standalone `Window` scenes provide the
/// Task Manager, Help, Tracker Browser, and Protocol Console surfaces.
@main
struct HeidrunMainApp: App {
    @NSApplicationDelegateAdaptor(HeidrunAppDelegate.self) private var appDelegate

    private let activeConnections = ActiveConnections.shared

    init() {
        // Opt out of macOS's app-level auto-resume of prior-session
        // windows — `SessionRestorationQueue` is the sole authority.
        // `restorationBehavior(.disabled)` only stops SwiftUI's scene
        // restoration, not the AppKit window-resume layer.
        UserDefaults.standard.register(defaults: [
            "NSQuitAlwaysKeepsWindows": false
        ])

        // Seed the session-restoration queue here, NOT from the app
        // delegate. SwiftUI fires the first scene's `.task` BEFORE
        // `applicationDidFinishLaunching`, so a delegate-driven load
        // would arrive too late and the first window's pump would bail
        // on an empty queue.
        MainActor.assumeIsolated {
            // Install the biometric-keychain policy BEFORE any
            // `saveOrLog` runs (auto-reconnect / session restoration
            // can fire a save inside the first scene's `.task`).
            let defaults = AppDataEnvironment.defaults
            let biometricToggle = defaults.bool(
                forKey: AppStorageKeys.useBiometricPasswordProtection
            )
            // Never use the biometric vault under the XCTest host — the
            // app target is the test host, so a "Unlock Heidrun saved
            // passwords" prompt would block unattended runs.
            KeychainPasswordStore.useBiometricACL = biometricToggle && !TestEnvironment.isRunningUnderTests

            // Isolated debug runs use an in-memory credential store so
            // the real keychain (and Touch ID) is never touched.
            if AppDataEnvironment.isIsolated {
                KeychainPasswordStore.mockBackend = InMemoryCredentialStore()
                SampleBookmarks.seedIfNeeded(into: BookmarkRegistry.shared, isIsolated: true)
            }

            // Skip session restoration under the test bundle. The XCTest
            // runner loads HeidrunAppTests INTO Heidrun.app, so this
            // init runs in the test process too — populating the queue
            // would auto-reconnect to the user's last live bookmark
            // mid-test and could trigger a `BiometricVaultKeyStore.unlock`
            // that silently regenerates the AES key, invalidating every
            // saved password encrypted under the prior key.
            guard !TestEnvironment.isRunningUnderTests else { return }

            let shouldReopen = (defaults.object(
                forKey: AppStorageKeys.reopenConnectionsOnLaunch
            ) as? Bool) ?? true
            guard shouldReopen else { return }
            SessionRestorationQueue.shared.populate(
                SessionRestorationStore(defaults: AppDataEnvironment.defaults).load()
            )
        }
    }

    var body: some Scene {
        DocumentGroup(newDocument: HeidrunBookmarkDocument.init) { configuration in
            RootView(
                document: configuration.document,
                fileURL: configuration.fileURL,
                features: FeatureRegistry.all
            )
            .environment(activeConnections)
            .frame(minWidth: 1100, minHeight: 720)
            .defaultAppStorage(AppDataEnvironment.defaults)
            .heidrunContentSizeFromStorage()
            .windowToolbarFullScreenVisibility(.onHover)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarLabelStyle(fixed: .iconOnly)
        .windowToolbarStyle(.unifiedCompact)
        .restorationBehavior(.disabled)
        // Route incoming hotline:// / heidrun:// URLs into an EXISTING
        // host window's `.onOpenURL` instead of SwiftUI auto-spawning an
        // extra empty form window per receipt.
        .handlesExternalEvents(matching: Set(["*"]))
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button {
                    AboutPanel.show()
                } label: {
                    Label("About Heidrun…", systemImage: "info.circle")
                }
            }
            // File → New / Open are provided by DocumentGroup. We replace
            // the rest of `.saveItem` (Save / Save As / Duplicate / Rename
            // / Move To / Revert To) which don't fit our bookmark-as-doc
            // model — but reinstate Close / Close All here because they
            // share the `.saveItem` placement and would disappear with
            // them otherwise.
            CommandGroup(replacing: .saveItem) {
                Button("Close") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: .command)

                Button("Close All") {
                    // `performClose` routes through `windowShouldClose`
                    // so a live connection still gets its prompt.
                    for window in NSApp.windows where window.isVisible {
                        window.performClose(nil)
                    }
                }
                .keyboardShortcut("w", modifiers: [.command, .option])
            }
            CommandGroup(after: .newItem) {
                Menu(content: {
                    RecentServersMenuContent()
                }, label: {
                    Label("Recent Servers", systemImage: "clock")
                })
            }
            CommandGroup(after: .newItem) {
                TrackerBrowserMenuItem()
            }
            CommandMenu("Connection") {
                FocusedConnectionCommands()
            }
            CommandMenu("Bookmarks") {
                BookmarksMenuContent()
            }
            CommandGroup(before: .textEditing) {
                NewsCommands()
            }
            CommandGroup(after: .windowList) {
                TaskManagerMenuItem()
                ProtocolConsoleMenuItem()
            }
            CommandGroup(replacing: .help) {
                HelpMenuItem()
            }
        }

        Window("Task Manager", id: WindowIDs.taskManager) {
            TaskManagerView()
                .environment(activeConnections)
                .defaultAppStorage(AppDataEnvironment.defaults)
                .heidrunContentSizeFromStorage()
        }
        .defaultSize(width: 760, height: 520)
        .commandsRemoved()

        Window("Heidrun Help", id: WindowIDs.help) {
            HelpView()
                .defaultAppStorage(AppDataEnvironment.defaults)
                .heidrunContentSizeFromStorage()
        }
        .defaultSize(width: 860, height: 580)
        .commandsRemoved()

        Window("Browse Trackers", id: WindowIDs.trackerBrowser) {
            TrackerWindowView()
                .defaultAppStorage(AppDataEnvironment.defaults)
                .heidrunContentSizeFromStorage()
        }
        .defaultSize(width: 860, height: 540)
        .commandsRemoved()

        Window("Protocol Console", id: WindowIDs.protocolConsole) {
            ProtocolConsoleView()
                .defaultAppStorage(AppDataEnvironment.defaults)
                .heidrunContentSizeFromStorage()
        }
        .defaultSize(width: 880, height: 480)
        .commandsRemoved()

        Settings {
            SettingsView()
                .defaultAppStorage(AppDataEnvironment.defaults)
                .heidrunContentSizeFromStorage()
        }
    }
}

enum WindowIDs {
    static let taskManager = "heidrun.task-manager"
    static let help = "heidrun.help"
    static let trackerBrowser = "heidrun.tracker-browser"
    static let protocolConsole = "heidrun.protocol-console"
}

private struct TaskManagerMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: WindowIDs.taskManager)
        } label: {
            Label("Task Manager", systemImage: "list.bullet.rectangle")
        }
        .keyboardShortcut("t", modifiers: [.command, .option])
    }
}

/// Hidden when `enableProtocolConsole` is off so it doesn't clutter the
/// menu for users who aren't debugging dialects.
private struct ProtocolConsoleMenuItem: View {
    @Environment(\.openWindow) private var openWindow
    @AppStorage(AppStorageKeys.enableProtocolConsole) private var enabled: Bool = false

    var body: some View {
        if enabled {
            Button {
                openWindow(id: WindowIDs.protocolConsole)
            } label: {
                Label("Protocol Console", systemImage: "terminal")
            }
            .keyboardShortcut("l", modifiers: [.command, .option, .shift])
        }
    }
}

private struct TrackerBrowserMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: WindowIDs.trackerBrowser)
        } label: {
            Label("Browse Trackers…", systemImage: "globe")
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])
    }
}

/// Replaces AppKit's auto-injected app-help entry. macOS Help Book bundles
/// need an Info.plist key + the helpbook indexer; a SwiftUI Window gives
/// us the same surface without that legacy plumbing.
private struct HelpMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            openWindow(id: WindowIDs.help)
        } label: {
            Label("Heidrun Help", systemImage: "questionmark.circle")
        }
        .keyboardShortcut("?", modifiers: [.command])
    }
}

/// macOS News menu. Acts on the focused threaded-news view via
/// `@FocusedValue(\.newsActionContext)`.
private struct NewsCommands: View {
    @FocusedValue(\.newsActionContext) private var context

    var body: some View {
        Button {
            context?.reply()
        } label: {
            Label("Reply…", systemImage: "arrowshape.turn.up.left")
        }
        .keyboardShortcut("r", modifiers: [.command])
        .disabled(context?.hasSelection != true)
        Divider()
        Button {
            context?.copyPost()
        } label: {
            Label("Copy Post", systemImage: "doc.on.doc")
        }
        .keyboardShortcut("c", modifiers: [.command, .option])
        .disabled(context?.hasSelection != true)
        Button {
            context?.copyThread()
        } label: {
            Label("Copy Thread", systemImage: "text.bubble")
        }
        .keyboardShortcut("c", modifiers: [.command, .option, .shift])
        .disabled(context?.hasSelection != true)
        Divider()
        Button {
            context?.edit()
        } label: {
            Label("Edit Post…", systemImage: "pencil")
        }
        .keyboardShortcut("e", modifiers: [.command, .option])
        .disabled(context?.canEdit != true)
        Button {
            context?.delete()
        } label: {
            Label("Delete Post…", systemImage: "trash")
        }
        .disabled(context?.hasSelection != true)
        Divider()
        Button {
            context?.copyBundleContents()
        } label: {
            Label("Copy Folder/Category Contents", systemImage: "folder")
        }
        .disabled(context?.hasSelectedBundle != true)
    }
}

private struct FocusedConnectionCommands: View {
    @FocusedValue(\.hostState) private var state
    private let bookmarkStore = BookmarkRegistry.shared

    var body: some View {
        Button {
            state?.retry()
        } label: {
            Label("Reconnect", systemImage: "arrow.clockwise")
        }
        .keyboardShortcut("r", modifiers: [.command])
        .disabled(state?.lastAttemptedSettings == nil)
        Button {
            state?.disconnect()
        } label: {
            Label("Disconnect", systemImage: "power")
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])
        .disabled(state?.isConnected != true)
        Divider()
        bookmarkButton
    }

    @ViewBuilder
    private var bookmarkButton: some View {
        let settings = state?.lastAttemptedSettings
        let existing = settings.flatMap { bookmarkStore.bookmark(matching: $0) }
        Button {
            guard let settings else { return }
            if let existing {
                bookmarkStore.remove(id: existing.id)
            } else {
                bookmarkStore.add(Bookmark(settings: settings))
            }
        } label: {
            if existing != nil {
                Label("Remove Bookmark", systemImage: "bookmark.slash")
            } else {
                Label("Bookmark", systemImage: "bookmark")
            }
        }
        .keyboardShortcut("d", modifiers: [.command])
        .disabled(settings == nil)
    }
}
