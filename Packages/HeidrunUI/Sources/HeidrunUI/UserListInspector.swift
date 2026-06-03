import SwiftUI
import HeidrunCore
import CommonTools

/// Trailing-column inspector showing the current server's user roster.
/// Selection drives the toolbar/context-menu actions; double-click is a
/// shortcut for "Send Message". The roster list itself is an AppKit
/// `NSTableView` (`UserTableView`) — a SwiftUI `Table` with a per-row
/// drag-out fights its own click selection.
public struct UserListInspector: View {
    @Bindable public var viewModel: UserListViewModel
    public var onSendMessage: (User) -> Void
    public var onStartPrivateChat: (User) -> Void
    public var onGetInfo: (User) -> Void
    public var onDisconnect: (User) -> Void
    /// Optional fetch for a user's full info. Retained for API stability
    /// (the AppKit row drag-out exports basic local info synchronously).
    public var fetchUserInfo: (@Sendable (User) async throws -> UserInfo)?
    /// Local "theme" — a banner stripe painted behind the whole user
    /// list. `0` (the default) means no backdrop.
    public var bannerID: UInt16

    @State private var selection: UInt16?

    public init(
        viewModel: UserListViewModel,
        bannerID: UInt16 = 0,
        onSendMessage: @escaping (User) -> Void,
        onStartPrivateChat: @escaping (User) -> Void = { _ in },
        onGetInfo: @escaping (User) -> Void,
        onDisconnect: @escaping (User) -> Void = { _ in },
        fetchUserInfo: (@Sendable (User) async throws -> UserInfo)? = nil
    ) {
        self.viewModel = viewModel
        self.bannerID = bannerID
        self.onSendMessage = onSendMessage
        self.onStartPrivateChat = onStartPrivateChat
        self.onGetInfo = onGetInfo
        self.onDisconnect = onDisconnect
        self.fetchUserInfo = fetchUserInfo
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            list
                .background(alignment: .top) { bannerBackdrop }
        }
    }

    /// Stretched 16x1 banner behind the user list — vertical color bands
    /// across the column. Low opacity so the rows stay legible. Only
    /// renders when `bannerID` resolves to a known banner.
    @ViewBuilder
    private var bannerBackdrop: some View {
        if bannerID != 0, let bannerImage = IconCatalog.shared.banners.cgImage(forID: Int(bannerID)) {
            Image(decorative: bannerImage, scale: 1, orientation: .up)
                .resizable()
                .interpolation(.medium)
                .opacity(0.35)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Header

    /// Compact action bar above the user list. Each button targets the
    /// currently-selected user; all four are disabled until the user
    /// picks a row. Same vertical metrics as the news/chat header so
    /// the three bars line up across the window.
    private var header: some View {
        HStack(spacing: Spacing.xxsmall.rawValue) {
            ActionButton(
                title: "Send Message",
                systemImage: "envelope",
                isEnabled: selectedUser != nil
            ) {
                if let user = selectedUser { onSendMessage(user) }
            }

            ActionButton(
                title: "Start Chat",
                systemImage: "bubble.left.and.bubble.right",
                isEnabled: selectedUser != nil
            ) {
                if let user = selectedUser { onStartPrivateChat(user) }
            }

            ActionButton(
                title: "Get Info",
                systemImage: "info.circle",
                isEnabled: selectedUser != nil
            ) {
                if let user = selectedUser { onGetInfo(user) }
            }

            Spacer(minLength: Spacing.xxsmall.rawValue)

            ActionButton(
                title: "Disconnect User",
                systemImage: "xmark.circle",
                isEnabled: selectedUser != nil,
                role: .destructive
            ) {
                if let user = selectedUser { onDisconnect(user) }
            }
        }
        .font(.subheadline)
        .padding(.horizontal, .small)
        .padding(.vertical, .xxxsmall)
        .padding(.horizontal, .xsmall)
        .frame(height: 40)
        .background(.background)
    }

    private var selectedUser: User? {
        guard let socket = selection else { return nil }
        return viewModel.users.first(where: { $0.socket == socket })
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 0) {
            if let loadError = viewModel.loadError {
                Text("Couldn't fetch user list: \(loadError)")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, .small)
                    .padding(.vertical, .xxsmall)
                Divider()
            }
            UserTableView(
                users: viewModel.users,
                selection: $selection,
                actions: UserRowActions(
                    sendMessage: onSendMessage,
                    startPrivateChat: onStartPrivateChat,
                    getInfo: onGetInfo,
                    disconnect: onDisconnect
                )
            )
            // Drop a stale selection when its user leaves.
            .onChange(of: viewModel.users) { _, _ in
                if let selectedSocket = selection,
                   !viewModel.users.contains(where: { $0.socket == selectedSocket }) {
                    selection = nil
                }
            }
        }
    }
}
