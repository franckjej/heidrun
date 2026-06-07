import Foundation
import AppKit
import Observation
import HeidrunCore
import HeidrunUI
import HeidrunChat
import HeidrunFiles
import HeidrunMessages
import HeidrunNews
import HeidrunAdmin

/// Per-connection bag of references the host window and TaskManager both
/// read from. Owns the long-lived feature VMs so chat history, file paths,
/// and the user roster survive module switches AND can be observed from a
/// second window. Created on `HostState`'s transition to `.connected`,
/// destroyed when it leaves. `cancel()` tears down every observation loop.
@MainActor
@Observable
final class ConnectionHandle: Identifiable {
    /// Unexpected disconnect flips to `.disconnected(reason:)` and leaves
    /// the handle in `ActiveConnections` so the TaskManager can offer
    /// Reconnect / Remove. User-initiated disconnect removes the handle
    /// entirely instead of leaving a tombstone.
    enum Phase: Sendable, Hashable {
        case connected
        case disconnected(reason: String?)
    }

    let id: UUID
    /// `var` so a TX 304 identity broadcast can sync `settings` with the
    /// wire state. The on-terminate session-restore snapshot reads
    /// `settings` per-handle — without this the restored connection
    /// would log in with the identity at *construction time* and skip
    /// whatever the user changed in Settings → Identity mid-session.
    var settings: ConnectionSettings
    let client: any HotlineClient
    let userListVM: UserListViewModel
    let chatVM: ChatViewModel
    let filesVM: FilesViewModel
    let messagesVM: MessagesViewModel
    /// News VMs hoisted here so the composer draft + browse state survive
    /// feature switches.
    let newsPlainVM: PlainNewsViewModel
    let newsThreadedVM: ThreadedNewsViewModel
    let soundCoordinator: SoundCoordinator
    let notificationCoordinator: NotificationCoordinator
    let broadcastVM: BroadcastViewModel
    /// Account-admin VM, hoisted here (like the others) so "Edit Account"
    /// from the roster can load an account into it before switching to the
    /// Admin module, and the editor state survives module switches.
    let adminVM: AdminViewModel

    /// Scene-scoped sink for user-facing errors. The feature VMs report
    /// into it via their `present` closures; `HostView` injects it into
    /// the environment and shows one alert bound to `current`.
    let errorPresenter: ErrorPresenter

    var phase: Phase = .connected

    /// The connected account's own privileges, from the server's "User
    /// Access" push (TX 354). UI-gating hint ONLY — the server enforces
    /// every privilege per request regardless. `hasPrivilegeInfo` tracks
    /// whether the server actually told us: gating is **fail-open** when it
    /// hasn't (server never sent 354, or a non-Heidrun server), so controls
    /// stay enabled and fall back to the optimistic "try → server-denied"
    /// path rather than disabling everything.
    private(set) var selfPrivileges: UserPrivileges = []
    private(set) var hasPrivilegeInfo: Bool = false
    private var privilegesTask: Task<Void, Never>?

    /// Enabled unless we KNOW the account lacks `privilege`. Fail-open while
    /// we have no privilege info.
    func permits(_ privilege: UserPrivileges) -> Bool {
        !hasPrivilegeInfo || selfPrivileges.contains(privilege)
    }

    /// Whether to enable the account-admin surface — any of the account
    /// **write** bits (or unknown privileges → fail-open). Deliberately
    /// excludes `.readUser` (canonically "Open User", bit 16): that's a
    /// view-only capability classic Hotline servers commonly grant guests,
    /// so counting it as "admin" wrongly lit up the Admin tab for MacDomain
    /// guests. Editing/creating/deleting accounts is what gates this.
    var canAdministerAccounts: Bool {
        !hasPrivilegeInfo
            || !selfPrivileges.isDisjoint(with: [.createUser, .modifyUser, .deleteUser])
    }

    /// Fetched via TX 212 `downloadBanner` shortly after login. `nil`
    /// while in flight or when the server has no banner.
    var serverBanner: ServerBanner?

    /// Captured by `WindowAccessor` on HostView mount. Used by the
    /// TaskManager to bring this window forward on row double-click.
    weak var window: NSWindow?

    /// Trampolines into the owning `HostState`. `[weak hostState]` so a
    /// closed window doesn't keep the handle alive forever.
    var onDisconnect: (() -> Void)?
    var onReconnect: (() -> Void)?
    var onRemove: (() -> Void)?

    var displayName: String {
        settings.name.isEmpty ? settings.address : settings.name
    }

    var isLive: Bool {
        if case .connected = phase { return true }
        return false
    }

    init(settings: ConnectionSettings, client: any HotlineClient) {
        let handleID = UUID()
        self.id = handleID
        self.settings = settings
        self.client = client
        let presenter = ErrorPresenter()
        self.errorPresenter = presenter
        let userListVM = UserListViewModel(client: client)
        self.userListVM = userListVM
        self.chatVM = ChatViewModel(client: client)
        // Captured-on-init so the transfer-completion closure and every
        // coordinator post carry a stable identifier the notification
        // click handler can match against `id.uuidString`.
        let hostIdentity = HostIdentity(
            id: handleID.uuidString,
            displayName: settings.name.isEmpty ? settings.address : settings.name
        )
        self.filesVM = FilesViewModel(
            client: client,
            downloadFolderURL: FilesFeature.resolveDownloadFolder,
            onTransferFinished: { transferState in
                guard case .completed = transferState.status else { return }
                SoundPlayer.shared.play(.fileDone)
                Task { @MainActor in
                    await NotificationCenterService.shared.post(
                        .transferFinished(
                            filename: transferState.displayName,
                            direction: transferState.direction
                        ),
                        host: hostIdentity
                    )
                }
            },
            metadataSeed: ConnectionHandle.metadataSeed(for: settings),
            present: { [presenter] error in presenter.present(error) }
        )
        self.messagesVM = MessagesViewModel(client: client, userList: userListVM)
        self.newsPlainVM = PlainNewsViewModel(
            client: client,
            present: { [presenter] error in presenter.present(error) }
        )
        self.newsThreadedVM = ThreadedNewsViewModel(
            client: client,
            present: { [presenter] error in presenter.present(error) }
        )
        self.soundCoordinator = SoundCoordinator(client: client)
        self.notificationCoordinator = NotificationCoordinator(
            client: client,
            host: hostIdentity,
            userList: userListVM
        )
        self.broadcastVM = BroadcastViewModel(client: client)
        self.adminVM = AdminViewModel(
            client: client,
            present: { [presenter] error in presenter.present(error) }
        )
    }

    /// Stamp each `.heidrunpart` with the server identity that produced
    /// it. `nonisolated` so tests can drive it without a live connection.
    /// `serverName` falls back to `address` — the Resume sheet's
    /// "From <serverName>" reads badly when the friendly name is empty.
    nonisolated static func metadataSeed(
        for settings: ConnectionSettings
    ) -> @Sendable () -> PartialDownloadMetadata.SeedFields? {
        let serverName = settings.name.isEmpty ? settings.address : settings.name
        let seed = PartialDownloadMetadata.SeedFields(
            serverAddress: settings.address,
            serverPort: settings.port,
            serverLogin: settings.login,
            serverName: serverName
        )
        return { seed }
    }

    /// Called once on connection ready. Idempotent because each VM's
    /// start is.
    func start() async {
        // Self-privileges from "User Access" (TX 354). Capture the event
        // stream first (so a push can't slip between seed and subscribe),
        // then seed from the recorded value (non-empty ⇒ the server pushed
        // it before we got here), then observe live re-pushes (e.g. an admin
        // editing our account mid-session). Fail-open stays intact: empty +
        // no event ⇒ hasPrivilegeInfo false ⇒ controls enabled.
        let eventStream = client.events
        privilegesTask = Task { [weak self] in
            for await event in eventStream {
                guard case let .userAccessReceived(privileges) = event else { continue }
                self?.selfPrivileges = privileges
                self?.hasPrivilegeInfo = true
                self?.filesVM.updatePrivileges(privileges)
                self?.newsPlainVM.updatePrivileges(privileges)
                self?.newsThreadedVM.updatePrivileges(privileges)
            }
        }
        let seededPrivileges = await client.connectionInfo.privileges
        if !seededPrivileges.isEmpty {
            selfPrivileges = seededPrivileges
            hasPrivilegeInfo = true
            filesVM.updatePrivileges(seededPrivileges)
            newsPlainVM.updatePrivileges(seededPrivileges)
            newsThreadedVM.updatePrivileges(seededPrivileges)
        }
        // Fetch the roster once and share with both chat (seeds its
        // join-event dedup set) and the user-list inspector. Otherwise
        // each VM fired its own TX 300, landing within 2 ms of each
        // other on every connect.
        let initialRoster: [User] = (try? await client.fetchUserList()) ?? []
        chatVM.seed(initialRoster: initialRoster)
        chatVM.start()
        messagesVM.start()
        newsPlainVM.start()
        await soundCoordinator.start()
        await notificationCoordinator.start()
        await broadcastVM.start()
        SoundPlayer.shared.play(.login)
        await notificationCoordinator.notifyConnected()
        await userListVM.start(initialRoster: initialRoster)
        // Fire-and-forget banner fetch. Any failure collapses to nil and
        // the HostView header just doesn't render the image strip.
        Task { @MainActor [weak self] in
            self?.serverBanner = try? await self?.client.downloadBanner()
        }
    }

    func cancel() {
        chatVM.cancel()
        messagesVM.cancel()
        newsPlainVM.cancel()
        soundCoordinator.cancel()
        notificationCoordinator.cancel()
        broadcastVM.cancel()
        userListVM.cancel()
        privilegesTask?.cancel()
        privilegesTask = nil
        SoundPlayer.shared.play(.logout)
    }

    /// Marks the handle dead but keeps it in the registry so the
    /// TaskManager can show the row. Stops the observation loops; leaves
    /// VM state intact (e.g. failed transfers stay visible). This is the
    /// only path that fires when the network drops without the server
    /// sending a clean close — when the server pushes `.disconnected`
    /// the notification also comes from `NotificationCoordinator`'s
    /// event loop.
    func markDisconnected(reason: String?) {
        guard case .connected = phase else { return }
        phase = .disconnected(reason: reason)
        let coordinator = notificationCoordinator
        // Post BEFORE `cancel()` so the coordinator is still alive.
        Task { @MainActor in
            await coordinator.notifyDisconnected(reason: reason)
        }
        cancel()
    }
}

extension ConnectionHandle: Hashable {
    nonisolated static func == (lhs: ConnectionHandle, rhs: ConnectionHandle) -> Bool {
        lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
