import SwiftUI
import CommonTools
import HeidrunCore
import HeidrunBookmarks
import HeidrunUI

/// Minimal payload from a tracker listing.
struct TrackerPick {
    let name: String
    let address: String
    let port: UInt16
}

/// Pre-connection screen: gather server + login details and hand the
/// `(ConnectionSettings, password)` pair to the caller. Password is passed
/// out-of-band so it never becomes part of the persisted bookmark.
struct ConnectionForm: View {
    let onConnect: (ConnectionSettings, String, Bool) -> Void
    var initialSettings: ConnectionSettings?

    /// Seeded at init time from `initialSettings` + `UserDefaults` so
    /// the form's first frame is already populated. Without this, the
    /// `@State` defaults render once before `.onAppear` hydration runs,
    /// producing a visible flash as TextFields snap from empty to
    /// filled and the icon picker swaps to the chosen icon.
    init(
        onConnect: @escaping (ConnectionSettings, String, Bool) -> Void,
        initialSettings: ConnectionSettings? = nil
    ) {
        self.onConnect = onConnect
        self.initialSettings = initialSettings
        let defaults = UserDefaults.standard
        let storedNickname = defaults.string(forKey: AppStorageKeys.defaultNickname)
            ?? NSFullUserName()
        let storedPort = (defaults.object(forKey: AppStorageKeys.defaultPort) as? Int) ?? 5500
        let storedIconID = (defaults.object(forKey: AppStorageKeys.defaultIconID) as? Int) ?? 0
        let storedEmoji = defaults.string(forKey: AppStorageKeys.defaultEmoji) ?? ""
        if let initial = initialSettings {
            self._name = State(initialValue: initial.name)
            self._address = State(initialValue: initial.address)
            self._port = State(initialValue: initial.port)
            self._useTLS = State(initialValue: initial.useTLS)
            self._pinnedCertificateSHA256 = State(initialValue: initial.pinnedCertificateSHA256)
            self._nickname = State(initialValue: initial.nickname)
            self._login = State(initialValue: initial.login)
            self._iconID = State(initialValue: initial.icon == 0 ? storedIconID : Int(initial.icon))
            self._emoji = State(initialValue: initial.emoji ?? (storedEmoji.isEmpty ? nil : storedEmoji))
        } else {
            self._nickname = State(initialValue: storedNickname)
            self._port = State(initialValue: UInt16(clamping: storedPort))
            self._iconID = State(initialValue: storedIconID)
            self._emoji = State(initialValue: storedEmoji.isEmpty ? nil : storedEmoji)
        }
    }

    @Environment(\.newDocument) private var newDocument
    @Environment(\.openDocument) private var openDocument

    @AppStorage(AppStorageKeys.defaultNickname) private var defaultNickname: String = NSFullUserName()
    @AppStorage(AppStorageKeys.defaultPort) private var defaultPort: Int = 5500
    @AppStorage(AppStorageKeys.defaultIconID) private var defaultIconID: Int = 0
    @AppStorage(AppStorageKeys.defaultEmoji) private var defaultEmoji: String = ""
    @AppStorage(AppStorageKeys.rememberRecents) private var rememberRecents: Bool = true

    @State private var name: String = ""
    @State private var address: String = ""
    @State private var port: UInt16 = 5500
    @State private var useTLS: Bool = false
    @State private var pinnedCertificateSHA256: String?
    @State private var nickname: String = ""
    @State private var login: String = ""
    @State private var password: String = ""
    @State private var rememberPassword: Bool = false
    @State private var autoReconnectOverride: AutoReconnectOverride = .inherit
    /// Per-bookmark identity overrides — hydrated from `initialSettings`,
    /// else seeded from Settings → Identity. Held as `@State` so reconnect
    /// returns the same icon/emoji that were saved, instead of silently
    /// overwriting them with the global default on every Connect (which
    /// would mark the doc edited even when nothing visibly changed).
    @State private var iconID: Int = 0
    @State private var emoji: String?
    private let recents = RecentsRegistry.shared
    @State private var bookmarks = BookmarkRegistry.shared
    @State private var sidebarSelection: Set<Bookmark.ID> = []
    private var selectedBookmarkID: Bookmark.ID? { singleBookmarkID(in: sidebarSelection) }
    @State private var droppedImport: PendingBookmarksImport?
    @State private var pendingSaveConfirmation = false
    /// Form-field snapshot captured on hydrate. `nil` when nothing is
    /// selected; otherwise compared against the live form to detect edits.
    @State private var editingBaseline: EditingBaseline?
    @State private var showingTrackerBrowser = false
    private struct BookmarkAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }
    @State private var bookmarkAlert: BookmarkAlert?

    /// Gates the form's first render so the window title + toolbar can
    /// settle off-screen before the content fades in. Without this the
    /// DocumentGroup-set filename title and pre-unified-toolbar style
    /// are visible for one frame and read as a flash + ~10pt shift.
    @State private var contentVisible = false

    var body: some View {
        NavigationSplitView {
            BookmarkSidebarView(
                store: bookmarks,
                selection: $sidebarSelection,
                onNew: handleNewBookmark,
                onDelete: handleDeleteBookmarks,
                onConnect: handleConnectFromBookmark,
                onConnectMany: handleConnectFromBookmarks,
                onImportLegacy: handleImportLegacy,
                onExportLegacy: handleExportLegacy,
                onExportCSV: handleExportCSV,
                onDropFile: handleDropFile
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 400)
            .opacity(contentVisible ? 1 : 0)
        } detail: {
            VStack(spacing: 8) {
                formColumn
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(contentVisible ? 1 : 0)
            .sheet(isPresented: $showingTrackerBrowser) {
                TrackerBrowser(
                    onPick: { server in
                        hydrate(fromTrackerPick: TrackerPick(
                            name: server.name,
                            address: server.address,
                            port: server.port
                        ))
                        showingTrackerBrowser = false
                    },
                    onCancel: { showingTrackerBrowser = false }
                )
            }
        }
        .onAppear {
            hydrateDefaults()
            // One run-loop tick lets the window title + toolbar style
            // settle (WindowAccessor pushes both synchronously on view-
            // mount, but the title-bar growth from .navigationSubtitle
            // can still animate). Then fade the content in.
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.18)) {
                    contentVisible = true
                }
            }
        }
        .onChange(of: sidebarSelection) { _, newValue in
            guard newValue.count == 1, let identifier = newValue.first,
                  let mark = bookmarks.bookmarks.first(where: { $0.id == identifier }) else {
                editingBaseline = nil
                return
            }
            hydrate(from: mark)
            editingBaseline = currentEditingBaseline()
        }
        .alert(item: $bookmarkAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .cancel(Text("OK"))
            )
        }
        .sheet(item: $droppedImport) { pending in
            BookmarksImportSheet(url: pending.url) { droppedImport = nil }
        }
        .alert(
            "Replace “\(selectedBookmarkDisplayName)”?",
            isPresented: $pendingSaveConfirmation
        ) {
            Button("Cancel", role: .cancel) { }
            Button("Save as New") { performSaveAsNew() }
            Button("Replace") { performReplace() }
        } message: {
            Text("You’ve changed the values for this bookmark. Replace it, or save your changes as a new bookmark?")
        }
        // Promote into the AppKit titlebar so the chrome stays populated
        // when tabbing between a form window and HostView (same slots).
        .navigationTitle("Connect to Hotline Server")
        .navigationSubtitle("Sign in to chat, browse files, and read news.")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                toolbarIcon
            }
        }
    }

    private var toolbarIcon: some View {
        Image("ToolbarAppIcon", bundle: .main)
            .resizable()
            .scaledToFit()
            .frame(width: 36, height: 34)
    }

    /// Extracted to keep `body` under the SwiftUI type-checker's budget —
    /// inlining all five sections + modifiers hits the "unable to type-
    /// check in reasonable time" wall.
    @ViewBuilder
    private var formColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !recents.entries.isEmpty {
                recentsMenu
            }
            serverSection
            identitySection
            autoReconnectSection
                .padding(.bottom, .small)
            footer
        }
        .padding(.horizontal, .small)
        .padding(.top, .small)
        .padding(.bottom, .small)
        .frame(maxWidth: 540)
    }

    private var recentsMenu: some View {
        Menu {
            ForEach(recents.entries, id: \.self) { entry in
                Button(menuLabel(for: entry)) { hydrate(from: entry) }
            }
        } label: {
            Label(
                "Recent: \(recents.entries.first.map(menuLabel) ?? "—")",
                systemImage: "clock.arrow.circlepath"
            )
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var serverSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                labeledField("Name") {
                    TextField("", text: $name, prompt: Text("Servername"))
                        .textFieldStyle(.roundedBorder)
                }
                labeledField("Address") {
                    HStack(spacing: 6) {
                        TextField("", text: $address, prompt: Text(verbatim: "hotline.example.com"))
                            .textFieldStyle(.roundedBorder)
                        if isCurrentSettingsBookmarked {
                            Image(systemName: "bookmark")
                                .foregroundStyle(.tint)
                                .help("This server is already saved as a bookmark.")
                        }
                    }
                }
                labeledField("Port") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            TextField("", value: $port, format: .number.grouping(.never))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 96)
                            Toggle("Use TLS", isOn: $useTLS)
                                .help("Connect over the server's TLS sibling port (encrypts chat, file listings, and downloads).")
                                .onChange(of: useTLS) { _, isOn in
                                    // Sibling-port convention: cleartext on
                                    // `port`, TLS on `port + 2`. Only flip
                                    // when the user hasn't typed a custom value.
                                    if isOn, port == 5500 {
                                        port = 5502
                                    } else if !isOn, port == 5502 {
                                        port = 5500
                                    }
                                }
                            Spacer(minLength: 0)
                        }
                        if useTLS, let pin = pinnedCertificateSHA256 {
                            HStack(spacing: 8) {
                                Text("Pinned cert: \(CertificateFingerprint.grouped(pin).prefix(17))…")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Button("Forget") { pinnedCertificateSHA256 = nil }
                                    .controlSize(.small)
                                    .help("Clear the trusted certificate; the next connection re-prompts. Save the bookmark to persist.")
                            }
                        }
                    }
                }
            }
            .padding(.xxsmall)
        } label: {
            Label("Server", systemImage: "server.rack")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var identitySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                labeledField("Nickname") {
                    TextField("", text: $nickname)
                        .textFieldStyle(.roundedBorder)
                }
                labeledField("Login") {
                    TextField("", text: $login, prompt: Text("Optional"))
                        .textFieldStyle(.roundedBorder)
                }
                labeledField("Password") {
                    SecureField("", text: $password, prompt: Text(passwordPrompt))
                        .textFieldStyle(.roundedBorder)
                }
                HStack(spacing: 10) {
                    Spacer().frame(width: labelColumnWidth)
                    Toggle("Remember password", isOn: $rememberPassword)
                        .disabled(login.isEmpty && password.isEmpty && !rememberPassword)
                    Spacer(minLength: 0)
                }
            }
            .padding(.xxsmall)
        } label: {
            Label("Identity", systemImage: "person")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var autoReconnectSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Text("Auto-reconnect")
                        .frame(width: labelColumnWidth, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $autoReconnectOverride) {
                        Text("Use default").tag(AutoReconnectOverride.inherit)
                        Text("Always reconnect").tag(AutoReconnectOverride.alwaysOn)
                        Text("Never reconnect").tag(AutoReconnectOverride.alwaysOff)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200, alignment: .leading)
                    Spacer(minLength: 0)
                }
            }
            .padding(.xxsmall)
        } label: {
            Label("Reconnect behavior", systemImage: "arrow.clockwise")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Button {
                showingTrackerBrowser = true
            } label: {
                Label("Browse Trackers…", systemImage: "magnifyingglass")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(saveButtonTitle) { saveBookmark() }
                .buttonStyle(.bordered)
                .disabled(!canSubmit)
            Button("Connect") { submit() }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!canSubmit)
                .buttonStyle(.borderedProminent)
        }
    }

    private var labelColumnWidth: CGFloat { 82 }

    @ViewBuilder
    private func labeledField<Field: View>(
        _ label: LocalizedStringKey,
        @ViewBuilder field: () -> Field
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .frame(width: labelColumnWidth, alignment: .trailing)
                .foregroundStyle(.secondary)
            field()
        }
    }

    private var canSubmit: Bool {
        !address.trimmingCharacters(in: .whitespaces).isEmpty
            && port > 0
            && !nickname.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Ellipsis signals a dialog will open (selected + edited); plain title
    /// otherwise — per macOS HIG.
    private var saveButtonTitle: LocalizedStringKey {
        hasUnsavedChanges ? "Save bookmark…" : "Save bookmark"
    }

    private var hasUnsavedChanges: Bool {
        guard let baseline = editingBaseline else { return false }
        return currentEditingBaseline() != baseline
    }

    private func currentEditingBaseline() -> EditingBaseline {
        EditingBaseline(
            name: name.trimmingCharacters(in: .whitespaces),
            address: address.trimmingCharacters(in: .whitespaces),
            port: port,
            useTLS: useTLS,
            pinnedCertificateSHA256: pinnedCertificateSHA256,
            nickname: nickname,
            login: login,
            autoReconnectOverride: autoReconnectOverride
        )
    }

    private var selectedBookmarkDisplayName: String {
        guard let identifier = selectedBookmarkID,
              let mark = bookmarks.bookmarks.first(where: { $0.id == identifier }) else {
            return ""
        }
        let trimmedName = mark.settings.name.trimmingCharacters(in: .whitespaces)
        return trimmedName.isEmpty ? mark.settings.address : trimmedName
    }

    /// True when a bookmark matches what's currently typed. Drives the
    /// bookmark glyph next to the Address field; advisory only.
    private var isCurrentSettingsBookmarked: Bool {
        let candidate = ConnectionSettings(
            name: name.trimmingCharacters(in: .whitespaces),
            address: address.trimmingCharacters(in: .whitespaces),
            port: port,
            nickname: nickname,
            login: login,
            useTLS: useTLS
        )
        return bookmarks.bookmark(matching: candidate) != nil
    }

    /// Field hydration now happens in `init` (synchronously, so the
    /// first frame is correct). All this leg has left to do is the
    /// keychain check, which derives the `Saved password will be used`
    /// placeholder from the saved-credentials index.
    private func hydrateDefaults() {
        if initialSettings != nil {
            hydratePasswordFromKeychain()
        }
    }

    /// Replace every form field from a tracker pick — deterministic so the
    /// previously-shown server's credentials never leak into the new one.
    /// Drop the bookmark selection so Save mints a new bookmark instead of
    /// silently overwriting the previous one.
    private func hydrate(fromTrackerPick pick: TrackerPick) {
        sidebarSelection = []
        editingBaseline = nil
        name = pick.name
        address = pick.address
        port = pick.port
        nickname = defaultNickname

        if let mark = bookmarks.bookmark(forAddress: pick.address, port: pick.port) {
            login = mark.settings.login
            useTLS = mark.settings.useTLS
            pinnedCertificateSHA256 = mark.settings.pinnedCertificateSHA256
            iconID = Int(mark.settings.icon)
            emoji = mark.settings.emoji
            hydratePasswordFromKeychain()
        } else if let savedLogin = KeychainPasswordStore.findAnyLogin(
            forAddress: pick.address, port: pick.port
        ) {
            login = savedLogin
            useTLS = false
            pinnedCertificateSHA256 = nil
            iconID = defaultIconID
            emoji = defaultEmoji.isEmpty ? nil : defaultEmoji
            hydratePasswordFromKeychain()
        } else {
            login = ""
            password = ""
            rememberPassword = false
            useTLS = false
            pinnedCertificateSHA256 = nil
            iconID = defaultIconID
            emoji = defaultEmoji.isEmpty ? nil : defaultEmoji
        }
    }

    /// Pre-set "Remember password" WITHOUT reading the keychain value. The
    /// full read is deferred to `submit()` so clicking through bookmarks
    /// never triggers an "allow access" prompt.
    private func hydratePasswordFromKeychain() {
        let key = KeychainPasswordStore.Key.canonical(
            address: address,
            port: port,
            login: login
        )
        password = ""
        rememberPassword = KeychainPasswordStore.hasSavedPassword(for: key)
    }

    private var passwordPrompt: String {
        if rememberPassword && password.isEmpty {
            return "Saved password will be used"
        }
        return "Optional"
    }

    private func submit() {
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        guard !trimmedAddress.isEmpty else { return }
        let settings = Self.connectionSettings(
            name: name,
            address: trimmedAddress,
            port: port,
            nickname: nickname,
            login: login,
            iconID: iconID,
            emoji: emoji,
            useTLS: useTLS,
            pinnedCertificateSHA256: pinnedCertificateSHA256
        )

        // Lazy keychain read — first "allow access" prompt lands here, once
        // per item per session. Session cache short-circuits subsequent
        // connect attempts to the same server.
        let effectivePassword: String
        if password.isEmpty, rememberPassword {
            let key = KeychainPasswordStore.Key.canonical(
                address: trimmedAddress,
                port: port,
                login: login
            )
            effectivePassword = KeychainPasswordStore.cachedOrRead(
                for: key,
                prompt: keychainPrompt(for: settings)
            ) ?? ""
        } else {
            effectivePassword = password
        }

        if rememberRecents { recents.record(settings) }
        onConnect(settings, effectivePassword, rememberPassword)
    }

    private func menuLabel(for settings: ConnectionSettings) -> String {
        let display = settings.name.isEmpty ? settings.address : settings.name
        return settings.login.isEmpty ? display : "\(display) (\(settings.login))"
    }

    private func hydrate(from entry: ConnectionSettings) {
        name = entry.name
        address = entry.address
        port = entry.port
        nickname = entry.nickname.isEmpty ? defaultNickname : entry.nickname
        login = entry.login
        useTLS = entry.useTLS
        pinnedCertificateSHA256 = entry.pinnedCertificateSHA256
        iconID = Int(entry.icon)
        emoji = entry.emoji
        // Recents stores no secrets; password comes from the keychain.
        hydratePasswordFromKeychain()
    }

    private func hydrate(from mark: Bookmark) {
        hydrate(from: mark.settings)
        autoReconnectOverride = mark.autoReconnect
    }

    private func saveBookmark() {
        guard !address.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if selectedBookmarkID == nil {
            performSaveAsNew()
        } else if hasUnsavedChanges {
            pendingSaveConfirmation = true
        } else {
            // Selected and unchanged: no-op for the entry but still run
            // the keychain policy below.
            performReplace()
        }
    }

    private func performReplace() {
        guard let identifier = selectedBookmarkID else { return }
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        bookmarks.update(Bookmark(
            id: identifier,
            settings: formSettings(address: trimmedAddress),
            autoReconnect: autoReconnectOverride
        ))
        persistPassword(forAddress: trimmedAddress, login: login)
        editingBaseline = currentEditingBaseline()
    }

    private func performSaveAsNew() {
        let trimmedAddress = address.trimmingCharacters(in: .whitespaces)
        let mark = Bookmark(
            settings: formSettings(address: trimmedAddress),
            autoReconnect: autoReconnectOverride
        )
        bookmarks.add(mark)
        sidebarSelection = [mark.id]
        persistPassword(forAddress: trimmedAddress, login: login)
        editingBaseline = currentEditingBaseline()
    }

    private func formSettings(address trimmedAddress: String) -> ConnectionSettings {
        Self.connectionSettings(
            name: name,
            address: trimmedAddress,
            port: port,
            nickname: nickname,
            login: login,
            iconID: iconID,
            emoji: emoji,
            useTLS: useTLS,
            pinnedCertificateSHA256: pinnedCertificateSHA256
        )
    }

    // `nonisolated static func connectionSettings(...)` lives in
    // `ConnectionForm+Settings.swift` (kept separate for the file-length lint cap).

    /// Mirror the post-`.connected` keychain policy so Save Bookmark alone
    /// (without a successful Connect) still persists the password — else an
    /// Export-as-Heidrun on a fresh save lands with `Password=""`.
    private func persistPassword(forAddress trimmedAddress: String, login: String) {
        let key = KeychainPasswordStore.Key.canonical(
            address: trimmedAddress,
            port: port,
            login: login
        )
        if rememberPassword, !password.isEmpty {
            KeychainPasswordStore.saveOrLog(password, for: key)
        } else if !rememberPassword {
            KeychainPasswordStore.deleteOrLog(for: key)
        }
    }

    private func handleNewBookmark() {
        sidebarSelection = []
        editingBaseline = nil
        name = ""
        address = ""
        port = UInt16(clamping: defaultPort)
        useTLS = false
        pinnedCertificateSHA256 = nil
        nickname = defaultNickname
        login = ""
        password = ""
        rememberPassword = false
        autoReconnectOverride = .inherit
    }

    private func handleDeleteBookmarks(_ ids: Set<Bookmark.ID>) {
        for identifier in ids {
            bookmarks.remove(id: identifier)
        }
        // Leave the form fields populated so an accidental delete doesn't
        // destroy unsaved edits.
        sidebarSelection.subtract(ids)
    }

    private func handleConnectFromBookmark(_ mark: Bookmark) {
        // Hydrate explicitly before submit — `.onChange(of:)` doesn't fire
        // when selection is unchanged AND its callbacks run AFTER the view
        // update. Idempotent with the `.onChange` hydrate.
        hydrate(from: mark)
        sidebarSelection = [mark.id]
        editingBaseline = currentEditingBaseline()
        submit()
    }

    /// Multi-bookmark double-click: claim the current window for the first
    /// and fan the rest across fresh host windows. Each opened file becomes
    /// its own window with `RootView.autoConnectFromDocument` taking over.
    private func handleConnectFromBookmarks(_ marks: [Bookmark]) {
        guard let firstMark = marks.first else { return }
        handleConnectFromBookmark(firstMark)
        for mark in marks.dropFirst() {
            if let url = bookmarks.url(for: mark) {
                Task { try? await openDocument(at: url) }
            } else {
                // File unexpectedly missing — pre-seed an untitled doc so
                // RootView.task still auto-connects.
                newDocument { HeidrunBookmarkDocument.seeded(with: mark.settings) }
            }
        }
    }

    private func handleDropFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            droppedImport = PendingBookmarksImport(url: destination)
        } catch {
            bookmarkAlert = BookmarkAlert(
                title: "Couldn't import bookmarks",
                message: error.localizedDescription
            )
        }
    }

    private func handleImportLegacy() {
        let imported = BookmarkFileActions.importLegacy(into: bookmarks) { title, message in
            bookmarkAlert = BookmarkAlert(title: title, message: message)
        }
        // Replaced roster invalidates the current selection.
        if imported != nil {
            handleNewBookmark()
        }
    }

    private func handleExportLegacy() {
        BookmarkFileActions.exportLegacy(from: bookmarks) { title, message in
            bookmarkAlert = BookmarkAlert(title: title, message: message)
        }
    }

    private func handleExportCSV() {
        BookmarkFileActions.exportCSV(from: bookmarks) { title, message in
            bookmarkAlert = BookmarkAlert(title: title, message: message)
        }
    }
}
