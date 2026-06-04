import SwiftUI
import HeidrunCore
import HeidrunUI
import CommonTools
import HeidrunChat
import HeidrunFiles
import HeidrunMessages
import HeidrunNews

struct HostView: View {
    let client: any HotlineClient
    let features: [any HeidrunFeature.Type]
    var state: HostState?

    @SceneStorage("Heidrun.selectedFeature") private var selectedIdentifier: String?
    @AppStorage(AppStorageKeys.defaultBannerID) private var defaultBannerID: Int = 0
    @State private var imRecipient: User?
    @State private var infoRecipient: User?
    @State private var disconnectCandidate: User?

    private var handle: ConnectionHandle? { state?.currentHandle }
    private var userListVM: UserListViewModel? { handle?.userListVM }
    private var chatVM: ChatViewModel? { handle?.chatVM }
    private var filesVM: FilesViewModel? { handle?.filesVM }
    private var messagesVM: MessagesViewModel? { handle?.messagesVM }
    private var newsPlainVM: PlainNewsViewModel? { handle?.newsPlainVM }
    private var newsThreadedVM: ThreadedNewsViewModel? { handle?.newsThreadedVM }
    private var broadcastVM: BroadcastViewModel? { handle?.broadcastVM }

    /// `address:port` for per-server preference scoping (window frames,
    /// sort orders) — unique within the user's bookmark set.
    private var serverIdentifier: String? {
        guard let settings = handle?.settings else { return nil }
        return "\(settings.address):\(settings.port)"
    }

    private var showsUserList: Bool {
        currentFeature()?.wantsUserListInspector ?? false
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .background(Color.clear)
        } detail: {
            detailPane
                .background(.background)
                .overlay(alignment: .bottom) {
                    if let state {
                        StatusBar(state: state, userCount: userListVM?.users.count, transferCount: activeTransferCount)
                            .padding([.bottom, .trailing], .xsmall)
                    }
                }
        }
        .navigationTitle(titleWithStatus)
        .navigationSubtitle(addressSubtitle)
        .toolbar {
            if let state {
                HostToolbar(state: state, transferCount: activeTransferCount)
            }
        }
        .background(WindowAccessor { window in
            // Park the window so the TaskManager can front it.
            handle?.window = window
            if let state, let window {
                let guardForWindow = state.closeGuard ?? HostWindowCloseGuard(state: state)
                state.closeGuard = guardForWindow
                guardForWindow.install(on: window)
            }
            // Toolbar-hairline suppression is at RootView level so it
            // covers the connecting / failed phases too.
        })
        .onAppear {
            if selectedIdentifier == nil {
                selectedIdentifier = features.first?.identifier
            }
            // Auto-switch to Messages on PM. Re-bind on every appearance
            // so a freshly-built handle's VM gets a live closure.
            messagesVM?.onIncomingMessage = { socket in
                selectedIdentifier = MessagesFeature.identifier
                messagesVM?.openThread(with: socket)
            }
        }
        .sheet(item: $imRecipient) { user in
            IMSendSheet(
                recipient: user,
                onSend: { body in
                    guard let vm = userListVM else {
                        throw NSError(
                            domain: "Heidrun.HostView",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Disconnected"]
                        )
                    }
                    try await vm.sendIM(to: user.socket, body: body)
                },
                onDismiss: { imRecipient = nil }
            )
        }
        .sheet(item: $infoRecipient) { user in
            UserInfoSheet(
                nickname: user.nickname,
                iconID: Int(user.icon),
                emoji: user.emoji,
                fetch: {
                    guard let vm = userListVM else {
                        throw NSError(
                            domain: "Heidrun.HostView",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "user list not ready"]
                        )
                    }
                    return try await vm.requestInfo(for: user.socket)
                },
                onDismiss: { infoRecipient = nil }
            )
        }
        .alert(
            "Disconnect \(disconnectCandidate?.nickname ?? "user")?",
            isPresented: Binding(
                get: { disconnectCandidate != nil },
                set: { if !$0 { disconnectCandidate = nil } }
            ),
            presenting: disconnectCandidate
        ) { user in
            Button("Disconnect", role: .destructive) {
                Task {
                    _ = try? await userListVM?.disconnect(socket: user.socket)
                    disconnectCandidate = nil
                }
            }
            Button("Cancel", role: .cancel) { disconnectCandidate = nil }
        } message: { _ in
            Text("They'll be dropped from the server. Server admin privileges may be required.")
        }
        .alert(
            "Server broadcast",
            isPresented: Binding(
                get: { broadcastVM?.current != nil },
                set: { presented in
                    if !presented { broadcastVM?.dismissCurrent() }
                }
            ),
            presenting: broadcastVM?.current
        ) { _ in
            Button("OK", role: .cancel) { }
        } message: { entry in
            Text(entry.message)
        }
        // Agreement sheet is at RootView level so it floats over
        // `ConnectingPane` while the connect Task waits for the user.
    }

    private var activeTransferCount: Int {
        filesVM?.transfers.values.filter { $0.status == .running }.count ?? 0
    }

    private var addressSubtitle: String {
        Self.addressSubtitle(for: state?.lastAttemptedSettings)
    }

    /// Lock emoji (🔒 TLS / 🔓 cleartext) — emoji not SF Symbol because
    /// the AppKit titlebar font can't render `Image(systemName:)`.
    nonisolated static func addressSubtitle(for settings: ConnectionSettings?) -> String {
        guard let settings else { return "" }
        // Double space because the subtitle is smaller than the title
        // and a single space reads too tight against the emoji.
        let lock = settings.useTLS ? "🔒 " : "🔓 "
        return "\(lock) \(settings.address):\(settings.port)"
    }

    private var titleWithStatus: String {
        guard let state else { return "Heidrun" }
        let dot = state.isConnected ? "🟢" : "🔴"
        return "\(dot) \(state.serverName)"
    }

    // MARK: - Layout variants

    /// Single NavigationSplitView structure across all features so
    /// toolbar placements stay stable when modules switch.
    @ViewBuilder
    private var detailPane: some View {
        if showsUserList {
            HSplitView {
                featureContent
                    .frame(minWidth: 300)
                userListColumn
                    .frame(minWidth: 220, idealWidth: 240, maxWidth: 320)
            }
        } else {
            featureContent
        }
    }

    // MARK: - Shared columns

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            serverBannerHeader
                .padding(.top, (Spacing.small.rawValue - Spacing.xxsmall.rawValue))
                .ignoresSafeArea(.container)
            Spacer()
            FeatureSidebarTableView(features: features, selection: $selectedIdentifier)
            Spacer()
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 280, max: 303)
    }

    /// Server banner (JPEG/GIF/BMP/PICT from TX 212). Empty for no
    /// banner; `.url` banners are unsupported in v1.
    @ViewBuilder
    private var serverBannerHeader: some View {
        if let banner = handle?.serverBanner,
           banner.kind != .url,
           let nsImage = NSImage(data: banner.data) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 100)
                .padding(.horizontal, .small)
                .padding(.vertical, .xxxsmall)
                .accessibilityLabel("Server banner")
        }
    }

    @ViewBuilder
    private var featureContent: some View {
        // Hoisted VMs (chat/files/news/messages) survive feature
        // switches. Everything else uses `makeContentView(client:)`.
        if selectedIdentifier == ChatFeature.identifier, let vm = chatVM {
            ChatView(viewModel: vm)
        } else if selectedIdentifier == FilesFeature.identifier, let vm = filesVM {
            FilesView(viewModel: vm, serverIdentifier: serverIdentifier)
        } else if selectedIdentifier == MessagesFeature.identifier, let vm = messagesVM {
            MessagesView(viewModel: vm)
        } else if selectedIdentifier == NewsFeature.identifier,
                  let plainVM = newsPlainVM, let threadedVM = newsThreadedVM {
            HostedNewsView(plain: plainVM, threaded: threadedVM, client: client)
        } else if let selected = currentFeature() {
            selected.makeContentView(client: client)
        } else {
            ContentUnavailableView(
                "Pick a feature",
                systemImage: "sidebar.left",
                description: Text("Choose a tab in the sidebar to get started.")
            )
        }
    }

    @ViewBuilder
    private var userListColumn: some View {
        if let vm = userListVM {
            UserListInspector(
                viewModel: vm,
                bannerID: UInt16(clamping: defaultBannerID),
                onSendMessage: { imRecipient = $0 },
                onStartPrivateChat: { user in
                    Task {
                        // Fire-and-forget; the ChatID surfaces via
                        // `privateChatJoined` for a future surface.
                        _ = try? await vm.startPrivateChat(with: user.socket)
                    }
                },
                onGetInfo: { infoRecipient = $0 },
                onDisconnect: { disconnectCandidate = $0 },
                fetchUserInfo: { user in try await vm.requestInfo(for: user.socket) }
            )
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func currentFeature() -> (any HeidrunFeature.Type)? {
        guard let selectedIdentifier else { return nil }
        return features.first(where: { $0.identifier == selectedIdentifier })
    }
}
