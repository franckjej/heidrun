import SwiftUI
import AppKit
import CommonTools
import HeidrunCore
import HeidrunUI
import HeidrunBookmarks

/// Dedupes duplicate `.onOpenURL` deliveries. macOS routes one incoming URL
/// to every `RootView` instance, so without this a single `hotline://` link
/// with N windows already open would spawn N duplicate connections.
@MainActor
enum URLDispatchGuard {
    private static let dedupeWindow: TimeInterval = 1.0
    private static var lastURL: URL?
    private static var lastAt: Date = .distantPast

    static func shouldHandle(_ url: URL) -> Bool {
        let now = Date()
        if url == lastURL, now.timeIntervalSince(lastAt) < dedupeWindow {
            return false
        }
        lastURL = url
        lastAt = now
        return true
    }
}

struct RootView: View {
    @ObservedObject var document: HeidrunBookmarkDocument
    /// `nil` for untitled docs; used to gate doc-app affordances (save-dirty,
    /// file-proxy icon) that don't fit a cold-launch form window.
    let fileURL: URL?
    let features: [any HeidrunFeature.Type]
    @State private var state = HostState()
    @State private var partialOpenHandler = PartialDownloadOpenHandler()
    @Environment(\.newDocument) private var newDocument
    @Environment(\.openWindow) private var openWindow
    @Environment(\.undoManager) private var undoManager
    @AppStorage(AppStorageKeys.defaultNickname) private var defaultNickname: String = NSFullUserName()
    @AppStorage(AppStorageKeys.defaultIconID) private var defaultIconID: Int = 0
    @AppStorage(AppStorageKeys.defaultEmoji) private var defaultEmoji: String = ""
    /// Mirror of `state.phase`'s failure payload as plain `@State`. Reading
    /// `@Observable` properties inside a Binding's `get` closure does NOT
    /// register as a dependency, so a Binding directly off `state.phase`
    /// fails to repaint the alert when the connect Task throws.
    @State private var failureMessage: String?
    @State private var hostWindow: NSWindow?

    private var phaseFailureMessage: String? {
        if case let .failed(message) = state.phase { return message }
        return nil
    }

    /// Phase-aware window title. `navigationTitle` doesn't beat DocumentGroup's
    /// auto-set "Untitled" / filename string, so we set `window.title` directly.
    private var preferredWindowTitle: String {
        switch state.phase {
        case .disconnected, .failed:
            return "Heidrun"
        case .connecting(let settings):
            let name = settings.name.isEmpty ? settings.address : settings.name
            return "🟢 \(name)"
        case .connected:
            let dot = state.isConnected ? "🟢" : "🔴"
            return "\(dot) \(state.serverName)"
        }
    }

    /// Document's saved identity wins when file-backed; otherwise carry the
    /// last attempted settings across a failed connect.
    private var initialFormSettings: ConnectionSettings? {
        if !document.settings.address.isEmpty {
            return document.settings
        }
        return state.lastAttemptedSettings
    }

    /// Peek the queue / document at body-time so a window about to auto-
    /// connect renders `ConnectingPane` on its FIRST frame instead of flashing
    /// `ConnectionForm` before `.task` fires.
    private var renderingPhase: HostState.Phase {
        if case .disconnected = state.phase,
           state.lastAttemptedSettings == nil {
            if !document.settings.address.isEmpty {
                return .connecting(document.settings)
            }
            if let pendingSettings = SessionRestorationQueue.shared.peek() {
                return .connecting(pendingSettings)
            }
        }
        return state.phase
    }

    /// File → Open on a `.heidrunbookmark` just mounted us with persisted
    /// settings — kick off the connect on `.task`.
    private var shouldAutoConnectFromDocument: Bool {
        guard case .disconnected = state.phase,
              state.lastAttemptedSettings == nil,
              !document.settings.address.isEmpty else { return false }
        return true
    }

    var body: some View {
        Group {
            switch renderingPhase {
            case .disconnected, .failed:
                ConnectionForm(
                    onConnect: { settings, password, rememberPassword in
                        var nextBookmark = document.bookmark
                        nextBookmark.settings = settings
                        if fileURL != nil {
                            // File-backed: register an undo so DocumentGroup
                            // enables ⌘S for saving back to the same file.
                            document.updateBookmark(nextBookmark, undoManager: undoManager)
                        } else {
                            // Untitled cold-launch form: mirror without undo,
                            // else every Connect marks the doc edited and ⌘S
                            // prompts for a Save As location.
                            document.bookmark = nextBookmark
                        }
                        state.connect(
                            settings: settings,
                            password: password,
                            rememberPassword: rememberPassword
                        )
                    },
                    initialSettings: initialFormSettings
                )
            case .connecting(let connectingSettings):
                ConnectingPane(
                    serverName: connectingSettings.name.isEmpty
                        ? connectingSettings.address
                        : connectingSettings.name,
                    reconnectStatus: state.autoReconnectCoordinator.isReconnecting
                        ? (attempt: state.autoReconnectCoordinator.attempt,
                           max: state.autoReconnectCoordinator.maxAttempts)
                        : nil,
                    onCancel: {
                        // Snapshot the flag BEFORE cancelConnect resets phase.
                        let shouldCloseWindow = state.isQueueSpawned
                        state.cancelConnect()
                        if shouldCloseWindow {
                            hostWindow?.close()
                        }
                    }
                )
            case .connected(let client):
                HostView(client: client, features: features, state: state)
            }
        }
        .focusedValue(\.hostState, state)
        .background(WindowAccessor { window in
            // Mark non-restorable so AppKit stops persisting per-window state
            // at quit — pairs with the NSQuitAlwaysKeepsWindows=off default.
            window?.isRestorable = false
            if fileURL == nil {
                window?.representedURL = nil
            }
            // Set window.title directly: SwiftUI's `navigationTitle` loses to
            // DocumentGroup's auto-set string in the connected phase too.
            // This closure re-fires on every body update so phase changes
            // naturally re-stamp the title.
            window?.title = preferredWindowTitle
            // Unified style: titlebar + toolbar render as one region instead
            // of stacked rows with a hairline between them.
            if let window {
                window.toolbarStyle = .unified
                ToolbarSeparatorSuppressor.install(on: window)
            }
            // @State write deferred — WindowAccessor now fires sync from
            // viewDidMoveToWindow which can land mid view-update;
            // mutating @State synchronously trips "Modifying state
            // during view update" warnings.
            DispatchQueue.main.async {
                hostWindow = window
            }
        })
        .onChange(of: phaseFailureMessage, initial: true) { _, newMessage in
            failureMessage = newMessage
        }
        .task {
            state.persistTrustedCertificate = { address, port, login, sha256 in
                BookmarkRegistry.shared.updatePinnedCertificate(
                    address: address,
                    port: port,
                    login: login,
                    sha256: sha256
                )
            }
            // File-backed doc auto-connect and queue-pump are mutually
            // exclusive: file-backed has its own settings; the queue is for
            // untitled docs from URL links / multi-bookmark double-click.
            if shouldAutoConnectFromDocument {
                autoConnectFromDocument()
            } else {
                await pumpSessionRestoration()
            }
        }
        // Skip during termination — SwiftUI also fires onDisappear for every
        // window when the process is shutting down, and disconnecting would
        // wipe the still-live snapshot `applicationWillTerminate` is about
        // to save. of course it will!
        .onDisappear {
            guard !HeidrunAppDelegate.isTerminating else { return }
            state.disconnect()
        }
        .alert(
            "Couldn't connect to \(state.serverName)",
            isPresented: Binding(
                get: { failureMessage != nil },
                set: { presenting in
                    if !presenting {
                        failureMessage = nil
                        if case .failed = state.phase {
                            state.phase = .disconnected
                        }
                    }
                }
            ),
            presenting: failureMessage
        ) { _ in
            Button("Try Again") {
                failureMessage = nil
                state.retry()
            }
            Button("Edit Connection", role: .cancel) {
                failureMessage = nil
                state.phase = .disconnected
            }
        } message: { reason in
            Text(reason)
        }
        .sheet(item: Binding(
            get: { state.pendingAgreement },
            set: { if $0 == nil { state.pendingAgreement = nil } }
        )) { prompt in
            AgreementSheet(
                prompt: prompt,
                onAccept: { state.acceptAgreement() },
                onDecline: { state.declineAgreement() }
            )
        }
        .sheet(item: Binding(
            get: { state.pendingCertificateChallenge },
            set: { if $0 == nil { state.resolveCertificate(.reject) } }
        )) { challenge in
            CertificateTrustSheet(challenge: challenge) { decision in
                state.resolveCertificate(decision)
            }
        }
        .onOpenURL(perform: handleIncomingURL)
        .onReceive(
            NotificationCenter.default.publisher(for: .heidrunHotlineLinkClicked),
            perform: handleHotlineLinkClickNote
        )
        .sheet(item: Binding(
            get: { state.pendingResume },
            set: { if $0 == nil { state.pendingResume = nil } }
        )) { request in
            ResumePartialSheet(
                request: request,
                onResume: {
                    state.requestPartialResume(request)
                    state.pendingResume = nil
                },
                onReveal: {
                    NSWorkspace.shared.activateFileViewerSelecting([request.url])
                    state.pendingResume = nil
                },
                onCancel: { state.pendingResume = nil }
            )
        }
        .sheet(item: Binding(
            get: { state.pendingUnreadablePartial },
            set: { if $0 == nil { state.pendingUnreadablePartial = nil } }
        )) { value in
            PartialUnreadableSheet(
                value: value,
                onReveal: {
                    NSWorkspace.shared.activateFileViewerSelecting([value.url])
                    state.pendingUnreadablePartial = nil
                },
                onDelete: {
                    try? FileManager.default.trashItem(at: value.url, resultingItemURL: nil)
                    state.pendingUnreadablePartial = nil
                },
                onDismiss: { state.pendingUnreadablePartial = nil }
            )
        }
        .sheet(item: Binding(
            get: { state.pendingBookmarksImport },
            set: { if $0 == nil { state.pendingBookmarksImport = nil } }
        )) { pending in
            BookmarksImportSheet(
                url: pending.url,
                onDismiss: { state.pendingBookmarksImport = nil }
            )
        }
    }

    /// Single dispatch point for every URL the system delivers — extracted
    /// to dedupe per-window deliveries and to keep the body short enough for
    /// the SwiftUI type-checker (inlining would tip it into "unable to type-
    /// check in reasonable time").
    @MainActor
    private func handleIncomingURL(_ url: URL) {
        guard URLDispatchGuard.shouldHandle(url) else { return }
        if url.pathExtension == "heidrunbookmarks" {
            state.pendingBookmarksImport = PendingBookmarksImport(url: url)
            return
        }
        if let settings = HotlineURLParser.parse(url) {
            openHotlineConnection(settings)
            return
        }
        switch partialOpenHandler.handle(url: url) {
        case .resume(let request):
            state.pendingResume = request
        case .unreadable(let value):
            state.pendingUnreadablePartial = value
        case .ignore:
            break
        }
    }

    /// Launch (or focus) a connection for a URL-dispatched
    /// `hotline://` / `heidrun://` link.
    @MainActor
    private func openHotlineConnection(_ settings: ConnectionSettings) {
        // URL-derived settings carry no identity — inject Settings defaults
        // so the login arrives as the user instead of "guest" (HostState
        // skips the login transaction on an empty nickname).
        let enriched = settingsWithIdentityDefaults(settings)
        // No-login URL (`hotline://server`) → match on address+port only so
        // re-clicking focuses an existing connection. With an explicit login
        // (`hotline://user@server`) require the full match.
        let urlSpecifiesLogin = !settings.login.isEmpty
        let liveHandle = ActiveConnections.shared.connections.first { handle in
            guard handle.isLive else { return false }
            guard handle.settings.address == enriched.address,
                  handle.settings.port == enriched.port else { return false }
            return !urlSpecifiesLogin || handle.settings.login == enriched.login
        }
        if let liveHandle, let window = liveHandle.window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        RecentsRegistry.shared.record(enriched)
        newDocument { HeidrunBookmarkDocument.seeded(with: enriched) }
    }

    /// In-app link clicks (chat / news / PM transcripts) skip
    /// `NSWorkspace.open` and post a notification so macOS doesn't auto-
    /// spawn an extra empty window for the URL on top of the one we open.
    @MainActor
    private func handleHotlineLinkClickNote(_ notification: Notification) {
        guard let clickedURL = notification.userInfo?[HotlineLinkClick.urlKey] as? URL else {
            return
        }
        handleIncomingURL(clickedURL)
    }

    private func settingsWithIdentityDefaults(_ source: ConnectionSettings) -> ConnectionSettings {
        var out = source
        if out.nickname.isEmpty { out.nickname = defaultNickname }
        if out.icon == 0 { out.icon = UInt16(clamping: defaultIconID) }
        if (out.emoji ?? "").isEmpty {
            out.emoji = defaultEmoji.isEmpty ? nil : defaultEmoji
        }
        return out
    }

    /// Auto-connect from a freshly-opened `.heidrunbookmark`. Marked queue-
    /// spawned so a cancel-during-connect closes the window — matches the
    /// URL-launch / multi-bookmark semantics (the user opened the doc to
    /// connect, not to land on an empty form).
    @MainActor
    private func autoConnectFromDocument() {
        let settings = document.settings
        let keychainKey = KeychainPasswordStore.Key.canonical(
            address: settings.address,
            port: settings.port,
            login: settings.login
        )
        let savedPassword = KeychainPasswordStore.cachedOrRead(
            for: keychainKey,
            prompt: keychainPrompt(for: settings)
        ) ?? ""
        state.isQueueSpawned = true
        state.connect(
            settings: settings,
            password: savedPassword,
            rememberPassword: true
        )
    }

    /// Claim one entry from `SessionRestorationQueue` and kick off its
    /// connect. If the queue isn't empty afterwards, open another host
    /// window so its `RootView.task` picks up the next entry — chained
    /// one-at-a-time for deterministic FIFO order.
    @MainActor
    private func pumpSessionRestoration() async {
        guard let settings = SessionRestorationQueue.shared.dequeue() else { return }
        // Skip if the user has already started typing into this window —
        // restored sessions shouldn't hijack in-progress edits.
        guard case .disconnected = state.phase, state.lastAttemptedSettings == nil else {
            return
        }
        let keychainKey = KeychainPasswordStore.Key.canonical(
            address: settings.address,
            port: settings.port,
            login: settings.login
        )
        let savedPassword = KeychainPasswordStore.cachedOrRead(
            for: keychainKey,
            prompt: keychainPrompt(for: settings)
        ) ?? ""
        state.isQueueSpawned = true
        // `rememberPassword: true` keeps the entry alive across restores. A
        // login that succeeds without visiting the form mustn't silently
        // delete a previously-saved password.
        state.connect(
            settings: settings,
            password: savedPassword,
            rememberPassword: true
        )
        if !SessionRestorationQueue.shared.isEmpty {
            // Defer so DocumentGroup's focus/scene-id bookkeeping settles
            // before we ask it to spawn another instance.
            DispatchQueue.main.async {
                newDocument { HeidrunBookmarkDocument() }
            }
        }
    }
}
