import Foundation
import Observation
import CommonTools
import HeidrunCore

/// One pending server agreement banner. `id` rotates per push so SwiftUI's
/// `.sheet(item:)` re-presents on a fresh agreement.
struct AgreementPrompt: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let autoAgree: Bool
}

/// Connection state machine the app's scene observes. Lives at the root
/// so disconnect/reconnect collapses the whole feature UI cleanly.
@Observable
@MainActor
final class HostState {
    enum Phase {
        case disconnected
        case connecting(ConnectionSettings)
        case connected(any HotlineClient)
        case failed(String)
    }

    typealias Connector = @Sendable (
        ConnectionSettings, String, @escaping CertificateTrustEvaluator
    ) async throws -> any HotlineClient

    var phase: Phase = .disconnected
    var lastAttemptedSettings: ConnectionSettings?

    @ObservationIgnored var closeGuard: HostWindowCloseGuard?
    private(set) var currentHandle: ConnectionHandle?
    var pendingAgreement: AgreementPrompt?

    var pendingCertificateChallenge: CertificateTrustChallenge?
    private var certificateContinuation: CheckedContinuation<CertificateTrustDecision, Never>?

    /// Injected by the app: persist a newly-trusted fingerprint onto the
    /// bookmark matching (address, port, login). Default no-op for tests /
    /// unsaved connections.
    var persistTrustedCertificate:
        (@MainActor (_ address: String, _ port: UInt16, _ login: String, _ sha256: String) -> Void) = { _, _, _, _ in }

    var pendingResume: PartialResumeRequest?
    var pendingUnreadablePartial: PartialDownloadUnreadable?
    var pendingBookmarksImport: PendingBookmarksImport?
    var pendingPostConnectResume: PartialResumeRequest?

    private let connector: Connector
    let autoReconnectCoordinator: AutoReconnectCoordinator
    private let connections: ActiveConnections
    private var connectTask: Task<Void, Never>?
    private var disconnectWatcher: Task<Void, Never>?
    private var agreementWatcher: Task<Void, Never>?

    private var pendingPassword: String = ""
    private var pendingRememberPassword: Bool = false
    private var pendingKeychainKey: KeychainPasswordStore.Key?

    /// `true` when this window was spawned by `SessionRestorationQueue` (URL
    /// launch, multi-bookmark double-click, Bookmarks menu) rather than typed
    /// into the form. `RootView` reads this on cancel — queue-spawned cancels
    /// close the window instead of dropping back to an empty form. Cleared on
    /// `.connected` so a later disconnect on a long session uses the form.
    @ObservationIgnored var isQueueSpawned: Bool = false

    init(
        connections: ActiveConnections = .shared,
        connector: @escaping Connector = HostState.defaultConnector,
        autoReconnectCoordinator: AutoReconnectCoordinator = AutoReconnectCoordinator()
    ) {
        self.connections = connections
        self.connector = connector
        self.autoReconnectCoordinator = autoReconnectCoordinator
    }

    var isConnected: Bool {
        if case .connected = phase { return true }
        return false
    }

    var serverName: String {
        guard let settings = lastAttemptedSettings else { return "—" }
        if !settings.name.isEmpty { return settings.name }
        return settings.address
    }

    /// Built once per connect. Runs off-main from the TLS verify queue and
    /// hops back to present the trust sheet.
    func certificateEvaluator() -> CertificateTrustEvaluator {
        { [weak self] challenge in
            await withCheckedContinuation { continuation in
                Task { @MainActor in
                    guard let self else { continuation.resume(returning: .reject); return }
                    self.certificateContinuation = continuation
                    self.pendingCertificateChallenge = challenge
                }
            }
        }
    }

    /// Called by the trust sheet's buttons. On trust we mirror the
    /// fingerprint onto `lastAttemptedSettings` (the in-flight connect Task
    /// reads it when it builds the handle) so the pin lands in the session-
    /// restoration snapshot and the user doesn't re-trust on every relaunch.
    func resolveCertificate(_ decision: CertificateTrustDecision) {
        if decision == .trust, let challenge = pendingCertificateChallenge {
            let fingerprint = challenge.presentedFingerprint
            persistTrustedCertificate(
                challenge.host,
                challenge.port,
                lastAttemptedSettings?.login ?? "",
                fingerprint
            )
            lastAttemptedSettings?.pinnedCertificateSHA256 = fingerprint
        }
        pendingCertificateChallenge = nil
        certificateContinuation?.resume(returning: decision)
        certificateContinuation = nil
    }

    func connect(
        settings: ConnectionSettings,
        password: String = "",
        rememberPassword: Bool = false
    ) {
        connectTask?.cancel()
        // Cancel watchers before kicking off the new connect so the prior
        // session's watcher can't race the new phase transitions.
        disconnectWatcher?.cancel()
        disconnectWatcher = nil
        agreementWatcher?.cancel()
        agreementWatcher = nil
        pendingAgreement = nil

        pendingPassword = password
        pendingRememberPassword = rememberPassword
        pendingKeychainKey = KeychainPasswordStore.Key.canonical(
            address: settings.address,
            port: settings.port,
            login: settings.login
        )

        // Capture the live client so the new connect Task can FIN it before
        // logging in — without this, reconnecting to the same server leaves
        // the server showing the user logged in twice.
        let previousClient: (any HotlineClient)?
        if case .connected(let client) = phase {
            previousClient = client
        } else {
            previousClient = nil
        }
        let previousHandle = currentHandle

        // Counter reset rule: a user-initiated connect to a DIFFERENT server
        // resets. Coordinator-driven retries go through `retryWithSavedPassword`
        // and bypass this branch so the counter keeps climbing.
        if lastAttemptedSettings != settings {
            autoReconnectCoordinator.reset()
        }
        lastAttemptedSettings = settings
        phase = .connecting(settings)

        let trustEvaluator = certificateEvaluator()
        connectTask = Task { [connector] in
            if let previousClient {
                await previousClient.disconnect()
            }
            if let previousHandle {
                previousHandle.cancel()
                connections.deregister(previousHandle.id)
            }
            currentHandle = nil

            do {
                let client = try await connector(settings, password, trustEvaluator)
                if Task.isCancelled {
                    await client.disconnect()
                    return
                }
                // Subscribe BEFORE login so the server's agreement push
                // (transID 109, sent right after the login reply) lands in
                // our watcher rather than vanishing. Non-blocking — servers
                // without 109 don't pay a timeout.
                await MainActor.run {
                    self.startWatchingAgreement(client: client)
                }
                if !settings.nickname.isEmpty {
                    // Identity fallback for re-login paths (reconnect, auto-
                    // connect from a file-backed doc, URL launches): bookmark
                    // fields holding `nil`/`0` mean "use Settings → Identity
                    // defaults" so the user's emoji doesn't silently vanish.
                    let defaults = UserDefaults.standard
                    let storedEmoji = defaults.string(forKey: AppStorageKeys.defaultEmoji) ?? ""
                    let resolvedEmoji = settings.emoji ?? (storedEmoji.isEmpty ? nil : storedEmoji)
                    let resolvedIcon: UInt16
                    if settings.icon == 0 {
                        resolvedIcon = UInt16(clamping: defaults.integer(forKey: AppStorageKeys.defaultIconID))
                    } else {
                        resolvedIcon = settings.icon
                    }
                    // Propagate login errors — eating server rejections (e.g.
                    // bad password) silently let the host continue into
                    // `.connected` as if auth had succeeded.
                    try await client.login(
                        name: settings.login,
                        password: password,
                        nickname: settings.nickname,
                        icon: resolvedIcon,
                        emoji: resolvedEmoji
                    )
                }
                if Task.isCancelled {
                    await client.disconnect()
                    return
                }

                // Prefer `lastAttemptedSettings` so a trust-on-first-use pin
                // added DURING this connect (inside the TLS handshake, before
                // the handle existed) lands on the handle and therefore in
                // the session-restoration snapshot.
                let handleSettings = lastAttemptedSettings ?? settings
                let handle = ConnectionHandle(settings: handleSettings, client: client)
                wireHandleCallbacks(handle)
                currentHandle = handle
                connections.register(handle)
                await handle.start()
                phase = .connected(client)
                isQueueSpawned = false
                autoReconnectCoordinator.reset()
                applyKeychainPolicyAfterConnect()
                startWatchingDisconnect(client: client)
                if let pending = pendingPostConnectResume {
                    pendingPostConnectResume = nil
                    Task { [weak self] in
                        await self?.completePartialResume(pending)
                    }
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self.pendingPostConnectResume = nil
                    self.pendingPassword = ""
                    self.pendingRememberPassword = false
                    self.pendingKeychainKey = nil

                    // Server-side rejection can't be recovered by waiting —
                    // stop the coordinator and surface the failure banner.
                    if case .serverError = (error as? HotlineError) {
                        self.autoReconnectCoordinator.cancel()
                        self.phase = .failed(Self.userMessage(for: error))
                        return
                    }

                    // Mid-retry-cycle failure → chain another scheduled
                    // attempt (the coordinator's own cap stops the chain at
                    // maxAttempts). Initial failures fall through to .failed.
                    if self.autoReconnectCoordinator.isReconnecting,
                       let settings = self.lastAttemptedSettings,
                       self.autoReconnectCoordinator.shouldAutoReconnect(
                           reason: nil,
                           settings: settings
                       ) {
                        self.phase = .connecting(settings)
                        self.autoReconnectCoordinator.scheduleRetry { [weak self] in
                            self?.retryWithSavedPassword()
                        }
                    } else {
                        self.phase = .failed(Self.userMessage(for: error))
                    }
                }
            }
        }
    }

    func disconnect() {
        // Local teardown FIRST so the watcher (about to see a `.disconnected`
        // for our own request) finds phase != .connected and skips the
        // `.failed` transition.
        disconnectWatcher?.cancel()
        disconnectWatcher = nil
        autoReconnectCoordinator.cancel()
        agreementWatcher?.cancel()
        agreementWatcher = nil
        pendingAgreement = nil
        pendingPostConnectResume = nil
        pendingPassword = ""
        pendingRememberPassword = false
        pendingKeychainKey = nil

        // Two teardown shapes: live `.connected` client (owe the server a
        // FIN), or mid-cycle auto-reconnect (coordinator already cancelled
        // above; `isReconnecting` is true because `cancel()` doesn't zero
        // the attempt counter).
        let liveClient: (any HotlineClient)?
        if case .connected(let client) = phase {
            liveClient = client
        } else if autoReconnectCoordinator.isReconnecting {
            liveClient = nil
        } else {
            return
        }

        // Cancel the in-flight connect Task so an orphan success can't flip
        // phase back to `.connected` after the user explicitly Disconnected.
        connectTask?.cancel()
        connectTask = nil

        phase = .disconnected
        if let handle = currentHandle {
            handle.cancel()
            connections.deregister(handle.id)
        }
        currentHandle = nil
        if let liveClient {
            Task { await liveClient.disconnect() }
        }
    }

    /// Dismiss the agreement sheet. We do NOT send TX 121 in response: the
    /// legacy client never put it on the wire (the Agreement nib had no
    /// Agree button), at least one server (MacDomain) closes the TCP on
    /// receiving it, and real servers don't gate access on the ack.
    func acceptAgreement() {
        pendingAgreement = nil
    }

    func declineAgreement() {
        pendingAgreement = nil
        disconnect()
    }

    func cancelConnect() {
        guard case .connecting = phase else { return }
        connectTask?.cancel()
        connectTask = nil
        autoReconnectCoordinator.cancel()
        pendingAgreement = nil
        pendingPostConnectResume = nil
        pendingPassword = ""
        pendingRememberPassword = false
        pendingKeychainKey = nil
        phase = .disconnected
    }

    /// User-initiated retry. Works from `.failed` and `.disconnected`. Resets
    /// the auto-reconnect counter; coordinator-driven retries use
    /// `retryWithSavedPassword` instead.
    func retry() {
        guard let settings = lastAttemptedSettings else { return }
        autoReconnectCoordinator.reset()
        connect(settings: settings, password: savedPassword(for: settings), rememberPassword: true)
    }

    /// Coordinator-initiated retry. Does NOT reset the counter — that's what
    /// distinguishes it from the user-initiated path.
    func retryWithSavedPassword() {
        guard let settings = lastAttemptedSettings else { return }
        connect(settings: settings, password: savedPassword(for: settings), rememberPassword: true)
    }

    /// Read the saved password via the session cache so reconnect cycles
    /// never re-prompt (the first connect already paid any Touch ID prompt).
    /// Returns "" when no entry exists.
    private func savedPassword(for settings: ConnectionSettings) -> String {
        let key = KeychainPasswordStore.Key.canonical(
            address: settings.address,
            port: settings.port,
            login: settings.login
        )
        return KeychainPasswordStore.cachedOrRead(
            for: key,
            prompt: keychainPrompt(for: settings)
        ) ?? ""
    }

    /// Begin a resume flow for a `.heidrunpart` the user double-clicked. If
    /// already connected to the matching server, re-issue the download
    /// in-place; otherwise reconstruct settings from the xattr and connect.
    func requestPartialResume(_ request: PartialResumeRequest) {
        pendingResume = nil
        pendingUnreadablePartial = nil

        if case .connected = phase,
           isCurrentConnectionMatching(request: request) {
            Task { [weak self] in
                await self?.completePartialResume(request)
            }
            return
        }

        let settings = Self.partialResumeSettings(
            for: request,
            defaults: UserDefaults.standard
        )
        lastAttemptedSettings = settings
        pendingPostConnectResume = request
        let key = KeychainPasswordStore.Key.canonical(
            address: settings.address,
            port: settings.port,
            login: settings.login
        )
        let savedPassword = KeychainPasswordStore.cachedOrRead(
            for: key,
            prompt: keychainPrompt(for: settings)
        ) ?? ""
        connect(settings: settings, password: savedPassword, rememberPassword: true)
    }

    /// Matches on `address` + `port` only — `login` is intentionally ignored
    /// so a partial started by another account on the same server still
    /// resumes through whoever is currently signed in.
    private func isCurrentConnectionMatching(request: PartialResumeRequest) -> Bool {
        guard let settings = lastAttemptedSettings else { return false }
        return settings.address == request.metadata.serverAddress
            && settings.port == request.metadata.serverPort
    }

    /// Build the settings handed to `connect()` for a `.heidrunpart` resume.
    /// The xattr only stores server identity; the user's nickname/icon come
    /// from `@AppStorage` defaults so the fresh login uses the configured
    /// identity rather than skipping the login transaction (which an empty
    /// nickname would trigger).
    static func partialResumeSettings(
        for request: PartialResumeRequest,
        defaults: UserDefaults = .standard
    ) -> ConnectionSettings {
        let storedNickname = defaults.string(forKey: AppStorageKeys.defaultNickname) ?? ""
        let nickname = storedNickname.isEmpty ? NSFullUserName() : storedNickname
        let iconID = UInt16(clamping: defaults.integer(forKey: AppStorageKeys.defaultIconID))
        let storedEmoji = defaults.string(forKey: AppStorageKeys.defaultEmoji)
        return ConnectionSettings(
            name: request.metadata.serverName,
            address: request.metadata.serverAddress,
            port: request.metadata.serverPort,
            nickname: nickname,
            login: request.metadata.serverLogin,
            icon: iconID,
            emoji: (storedEmoji?.isEmpty ?? true) ? nil : storedEmoji
        )
    }

    /// Finish the resume started by `requestPartialResume(_:)`: navigate to
    /// the recorded remote path and re-issue the download against the
    /// freshly-`.connected` client.
    private func completePartialResume(_ request: PartialResumeRequest) async {
        guard let filesViewModel = currentHandle?.filesVM else { return }
        let remote = request.metadata
        await filesViewModel.navigate(to: RemotePath(components: remote.remotePath))
        let entry = RemoteFile(
            name: remote.remoteFileName,
            type: .file,
            creator: .unknown,
            size: UInt32(clamping: remote.totalSize)
        )
        await filesViewModel.download(entry, mode: .resume)
    }

    /// Watch `client.events` for an `.agreementReceived` push (TX 109) and
    /// surface the prompt over the host view.
    private func startWatchingAgreement(client: any HotlineClient) {
        let stream = client.events
        agreementWatcher = Task { [weak self] in
            for await event in stream {
                if case let .agreementReceived(text, auto) = event {
                    await MainActor.run {
                        guard let self else { return }
                        self.pendingAgreement = AgreementPrompt(
                            text: text,
                            autoAgree: auto
                        )
                    }
                }
            }
        }
    }

    /// Watch `client.events` for an unexpected `.disconnected`. The host's
    /// own `disconnect()` cancels this watcher first so a user-initiated
    /// leave doesn't bounce through the failure banner.
    private func startWatchingDisconnect(client: any HotlineClient) {
        let stream = client.events
        disconnectWatcher = Task { [weak self] in
            for await event in stream {
                if case .disconnected(let reason) = event {
                    await MainActor.run {
                        guard let self else { return }
                        guard case .connected = self.phase else { return }

                        self.pendingAgreement = nil
                        let settings = self.lastAttemptedSettings
                        let shouldRetry: Bool = {
                            guard let settings else { return false }
                            return self.autoReconnectCoordinator.shouldAutoReconnect(
                                reason: reason,
                                settings: settings
                            )
                        }()

                        if shouldRetry, let settings {
                            self.currentHandle?.markDisconnected(reason: reason)
                            self.connections.persistLiveSnapshot()
                            self.phase = .connecting(settings)
                            self.autoReconnectCoordinator.scheduleRetry { [weak self] in
                                self?.retryWithSavedPassword()
                            }
                        } else {
                            // Leave the handle in the registry as a tombstone
                            // so the TaskManager can offer Reconnect / Remove.
                            self.phase = .failed(
                                reason.map(Self.cleanDisconnectReason) ?? "Connection lost."
                            )
                            self.currentHandle?.markDisconnected(reason: reason)
                            self.connections.persistLiveSnapshot()
                        }
                    }
                    return
                }
            }
        }
    }

    /// Wire the per-handle action closures so the TaskManager can drive
    /// disconnect / reconnect / remove. `[weak self]` so a closed window
    /// doesn't pin the state machine.
    private func wireHandleCallbacks(_ handle: ConnectionHandle) {
        handle.onDisconnect = { [weak self] in
            self?.disconnect()
        }
        handle.onReconnect = { [weak self] in
            self?.retry()
        }
        handle.onRemove = { [weak self, weak handle] in
            guard let self, let handle else { return }
            self.connections.deregister(handle.id)
            if self.currentHandle?.id == handle.id {
                self.currentHandle = nil
            }
            if case .failed = self.phase {
                self.phase = .disconnected
            }
        }
    }

    /// Save or delete the password according to the form's "Remember"
    /// choice. Runs only after `.connected` so we never persist a rejected
    /// password.
    private func applyKeychainPolicyAfterConnect() {
        guard let key = pendingKeychainKey else { return }
        let password = pendingPassword
        let remember = pendingRememberPassword
        // Clear the stash before IO so a re-entrancy can't double-apply.
        pendingPassword = ""
        pendingRememberPassword = false
        pendingKeychainKey = nil

        if remember {
            if !password.isEmpty {
                KeychainPasswordStore.saveOrLog(password, for: key)
            }
        } else {
            KeychainPasswordStore.deleteOrLog(for: key)
        }
    }

    private static let defaultConnector: Connector = { settings, _, evaluator in
        // Reading the developer-console toggle inline means a flip in
        // Settings takes effect on the NEXT connection — pre-existing
        // sessions keep their observer state.
        let defaults = AppDataEnvironment.defaults
        let consoleEnabled = defaults.bool(forKey: AppStorageKeys.enableProtocolConsole)
        // Unique per-connection token so the console correlates replies per
        // connection, not per server name — two sessions to the same host
        // no longer cross up each other's replies.
        let connectionID = UUID().uuidString
        let observer: PacketObserver? = consoleEnabled
            ? await MainActor.run {
                ProtocolConsoleStore.shared.observer(connectionID: connectionID, server: settings.address)
            }
            : nil
        return try await HotlineNetworkClient.connect(
            settings: settings,
            trustEvaluator: evaluator,
            packetObserver: observer
        )
    }

    private static func userMessage(for error: any Error) -> String {
        if let hotline = error as? HotlineError {
            return hotline.userMessage
        }
        return (error as NSError).localizedDescription
    }

    /// Lift the server-supplied detail out of a raw disconnect reason
    /// shaped like `"server error <n>: <detail>"`.
    private static func cleanDisconnectReason(_ rawReason: String) -> String {
        if let range = rawReason.range(of: "server error ") {
            let suffix = rawReason[range.upperBound...]
            if let colon = suffix.firstIndex(of: ":") {
                let detail = suffix[suffix.index(after: colon)...]
                    .trimmingCharacters(in: .whitespaces)
                if !detail.isEmpty {
                    return detail.prefix(1).uppercased() + detail.dropFirst()
                }
            }
            return "The server closed the connection."
        }
        return rawReason
    }
}
