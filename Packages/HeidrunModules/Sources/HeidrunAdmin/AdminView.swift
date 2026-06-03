import SwiftUI
import HeidrunCore
import CommonTools

/// NavigationSplitView-based account editor.
///
/// Sidebar shows the operator's session roster (accounts loaded or
/// created during this connection). The detail pane edits one draft at
/// a time, with grouped privilege disclosure groups and a role preset
/// picker.
public struct AdminView: View {
    @State private var viewModel: AdminViewModel
    @State private var showDeleteConfirmation = false
    @State private var pendingDeleteLogin: String?

    // Per-group expansion state for the privilege disclosure groups.
    @State private var filesExpanded = true
    @State private var chatExpanded = false
    @State private var newsExpanded = false
    @State private var usersExpanded = false
    @State private var serverExpanded = false

    public init(viewModel: AdminViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
            detail
                .frame(minWidth: 420)
        }
        .padding(.bottom, .xlarge)
        .alert(
            "Couldn't complete the operation",
            isPresented: Binding(
                get: { viewModel.lastError != nil },
                set: { value in if !value { viewModel.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.clearError() }
        } message: {
            Text(viewModel.lastError ?? "")
        }
        .confirmationDialog(
            "Delete \(pendingDeleteLogin ?? "")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = pendingDeleteLogin {
                    Task { await viewModel.deleteRow(login: target) }
                }
                pendingDeleteLogin = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteLogin = nil }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: Spacing.xsmall.rawValue) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find login", text: $viewModel.findQuery)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await viewModel.findAndLoad() } }
                Button {
                    viewModel.startNew()
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("New account")
            }
            .padding(.horizontal, .xsmall)
            .padding(.top, .small)

            GroupBox {
                List(selection: Binding(
                    get: { viewModel.selection },
                    set: { next in
                        if case let .existing(login) = next {
                            Task { await viewModel.selectExisting(login: login) }
                        } else {
                            viewModel.selection = next
                        }
                    }
                )) {
                    ForEach(viewModel.roster) { entry in
                        rosterRow(entry).tag(AdminViewModel.Selection.existing(login: entry.login))
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: false))
                .scrollContentBackground(.hidden)
                .frame(maxHeight: .infinity)
            }
            .background(.background)
            .padding(.horizontal, .xsmall)
            .padding(.bottom, .xsmall)
        }
    }

    @ViewBuilder
    private func rosterRow(_ entry: AdminViewModel.RosterEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.login).font(.body.monospaced())
                Text(entry.nickname).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if entry.isDirty {
                Circle().fill(.orange).frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, .xxsmall)
        .padding(.horizontal, .xxsmall)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Duplicate") {
                Task { await viewModel.duplicate(login: entry.login) }
            }
            Button("Delete", role: .destructive) {
                pendingDeleteLogin = entry.login
                showDeleteConfirmation = true
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if viewModel.selection == nil {
            ContentUnavailableView(
                "Pick an account",
                systemImage: "person.crop.circle.badge.questionmark",
                description: Text("Find a login or hit + to create one.")
            )
            .padding(.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        } else {
            Form {
                Section("Identity") {
                    TextField("Login", text: $viewModel.login)
                        .disabled(viewModel.loadedAccount != nil)
                        .textFieldStyle(.roundedBorder)
                    TextField("Nickname", text: $viewModel.nickname)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Password") {
                    if viewModel.loadedAccount != nil {
                        Toggle("Change password", isOn: $viewModel.changePassword)
                    }
                    if viewModel.loadedAccount == nil || viewModel.changePassword {
                        SecureField("Password", text: $viewModel.password)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Section("Preset") {
                    Picker("Preset", selection: Binding(
                        get: { viewModel.preset },
                        set: { next in viewModel.selectPreset(next) }
                    )) {
                        Text("Guest").tag(AdminPrivilegePresets.Name.guest)
                        Text("User").tag(AdminPrivilegePresets.Name.user)
                        Text("Moderator").tag(AdminPrivilegePresets.Name.moderator)
                        Text("Admin").tag(AdminPrivilegePresets.Name.admin)
                        Text("Custom").tag(AdminPrivilegePresets.Name.custom)
                    }
                    .pickerStyle(.menu)
                }

                privilegeGroup(title: "Files & Folders", privileges: Self.filePrivileges, isExpanded: $filesExpanded)
                privilegeGroup(title: "Chat", privileges: Self.chatPrivileges, isExpanded: $chatExpanded)
                privilegeGroup(title: "News", privileges: Self.newsPrivileges, isExpanded: $newsExpanded)
                privilegeGroup(title: "Users", privileges: Self.userPrivileges, isExpanded: $usersExpanded)
                privilegeGroup(title: "Server", privileges: Self.serverPrivileges, isExpanded: $serverExpanded)

                // Trailing breathing room so the last DisclosureGroup
                // doesn't sit flush against the action bar.
                Color.clear
                    .frame(height: Spacing.xsmall.rawValue)
                    .listRowBackground(Color.clear)
            }
            .formStyle(.grouped)
            .frame(minWidth: 420)
            .padding(.top, .xsmall)
            .safeAreaInset(edge: .bottom) {
                detailBottomBar
            }
        }
    }

    private var detailBottomBar: some View {
        HStack {
            Button(role: .destructive) {
                if let loaded = viewModel.loadedAccount {
                    pendingDeleteLogin = loaded
                    showDeleteConfirmation = true
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(viewModel.loadedAccount == nil || viewModel.isWorking)

            Spacer()

            noticeLabel
                .padding(.trailing, .xsmall)

            Button("Revert") {
                Task { await viewModel.revert() }
            }
            .disabled(!viewModel.isDirty || viewModel.loadedAccount == nil || viewModel.isWorking)

            Button("Save") {
                Task { await viewModel.save() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(saveDisabled)
        }
        .padding(.horizontal, .small)
        .padding(.vertical, .xsmall)
        .background(.background)
    }

    /// Transient confirmation label that fades in/out next to the
    /// Revert / Save buttons. Backed by `viewModel.lastNotice`, which
    /// auto-clears after a few seconds.
    @ViewBuilder
    private var noticeLabel: some View {
        if let notice = viewModel.lastNotice {
            HStack(spacing: 4) {
                Image(systemName: noticeIcon(for: notice))
                    .foregroundStyle(noticeTint(for: notice))
                Text(notice.message)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            .animation(.easeInOut(duration: 0.2), value: notice)
        }
    }

    private func noticeIcon(for notice: AdminViewModel.Notice) -> String {
        switch notice {
        case .deleted:
            return "trash"
        case .reverted:
            return "arrow.uturn.backward"
        case .loaded:
            return "tray.and.arrow.down"
        case .created, .saved:
            return "checkmark.circle"
        }
    }

    private func noticeTint(for notice: AdminViewModel.Notice) -> Color {
        switch notice {
        case .deleted:
            return .orange
        default:
            return .green
        }
    }

    private var saveDisabled: Bool {
        if viewModel.isWorking { return true }
        if viewModel.login.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if viewModel.loadedAccount == nil && viewModel.password.isEmpty { return true }
        return false
    }

    @ViewBuilder
    private func privilegeGroup(
        title: String,
        privileges rows: [PrivilegeRow],
        isExpanded: Binding<Bool>
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            ForEach(rows, id: \.label) { row in
                Toggle(row.label, isOn: Binding(
                    get: { viewModel.binding(for: row.privilege) },
                    set: { value in viewModel.setPrivilege(row.privilege, on: value) }
                ))
            }
        } label: {
            Text(title).font(.headline)
        }
    }

    // MARK: - Privilege rows

    struct PrivilegeRow {
        let label: String
        let privilege: UserPrivileges
    }

    static let filePrivileges: [PrivilegeRow] = [
        .init(label: "Upload files", privilege: .uploadFiles),
        .init(label: "Download files", privilege: .downloadFiles),
        .init(label: "Delete files", privilege: .deleteFiles),
        .init(label: "Rename files", privilege: .renameFiles),
        .init(label: "Move files", privilege: .moveFiles),
        .init(label: "Create folders", privilege: .createFolders),
        .init(label: "Delete folders", privilege: .deleteFolders),
        .init(label: "Rename folders", privilege: .renameFolders),
        .init(label: "Move folders", privilege: .moveFolders),
        .init(label: "Comment files", privilege: .commentFiles),
        .init(label: "Comment folders", privilege: .commentFolders),
        .init(label: "Upload folders", privilege: .uploadFolders),
        .init(label: "Download folders", privilege: .downloadFolders),
        .init(label: "Upload anywhere", privilege: .uploadAnywhere),
        .init(label: "View drop boxes", privilege: .viewDropBoxes),
        .init(label: "Make aliases", privilege: .makeAliases)
    ]

    static let chatPrivileges: [PrivilegeRow] = [
        .init(label: "Read chat", privilege: .readChat),
        .init(label: "Send chat", privilege: .sendChat),
        .init(label: "Initiate private chat", privilege: .initiatePrivateChat),
        .init(label: "Close private chat", privilege: .closePrivateChat)
    ]

    static let newsPrivileges: [PrivilegeRow] = [
        .init(label: "Read news", privilege: .readNews),
        .init(label: "Post news", privilege: .postNews),
        .init(label: "Delete articles", privilege: .deleteArticles),
        .init(label: "Create categories", privilege: .createCategories),
        .init(label: "Delete categories", privilege: .deleteCategories),
        .init(label: "Create news bundles", privilege: .createNewsBundles),
        .init(label: "Delete news bundles", privilege: .deleteNewsBundles)
    ]

    static let userPrivileges: [PrivilegeRow] = [
        .init(label: "Create users", privilege: .createUser),
        .init(label: "Delete users", privilege: .deleteUser),
        .init(label: "Read users", privilege: .readUser),
        .init(label: "Modify users", privilege: .modifyUser),
        .init(label: "Change own password", privilege: .changeOwnPassword),
        .init(label: "Disconnect users", privilege: .disconnectUsers),
        .init(label: "Cannot be disconnected", privilege: .cannotBeDisconnected),
        .init(label: "Get user info", privilege: .getUserInfo)
    ]

    static let serverPrivileges: [PrivilegeRow] = [
        .init(label: "Broadcast", privilege: .canBroadcast),
        .init(label: "Use any name", privilege: .useAnyName),
        .init(label: "Skip agreement", privilege: .dontShowAgreement),
        .init(label: "Show in user list", privilege: .showInList),
        .init(label: "Send messages", privilege: .sendMessages)
    ]
}
