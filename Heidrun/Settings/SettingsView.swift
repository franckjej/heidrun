import SwiftUI
import AppKit
import CommonTools
import HeidrunUI
import UserNotifications

/// macOS preferences pane reached via `App → Settings…` (⌘,). Eight tabs;
/// every value persists via `@AppStorage`.
///
/// Visual contract shared across tabs: `tabBody(...)` wraps content in a
/// top-aligned ScrollView (so growing tabs stay usable); `labeledRow(...)`
/// uses a fixed-width right-aligned label column so rows line up. Integer
/// values render with `.number.grouping(.never)` — thousand separators
/// look like decimal points in locales where `,` / `.` is the decimal mark.
struct SettingsView: View {
    @AppStorage(AppStorageKeys.defaultNickname) private var defaultNickname: String = NSFullUserName()
    @AppStorage(AppStorageKeys.defaultIconID) private var defaultIconID: Int = 0
    @AppStorage(AppStorageKeys.defaultEmoji) private var defaultEmoji: String = ""
    @AppStorage(AppStorageKeys.defaultBannerID) private var defaultBannerID: Int = 0
    @AppStorage(AppStorageKeys.defaultPort) private var defaultPort: Int = 5500
    @AppStorage(AppStorageKeys.rememberRecents) private var rememberRecents: Bool = true
    @AppStorage(AppStorageKeys.autoReconnectEnabled) private var autoReconnectEnabled: Bool = false
    @AppStorage(AppStorageKeys.autoReconnectMaxAttempts) private var autoReconnectMaxAttempts: Int = 3
    @AppStorage(AppStorageKeys.autoReconnectDelaySeconds) private var autoReconnectDelaySeconds: Int = 5
    @AppStorage(SoundPlayer.enabledDefaultsKey) private var soundsEnabled: Bool = true
    @AppStorage(AppStorageKeys.showChatTimestamps) private var showChatTimestamps: Bool = false
    @AppStorage(AppStorageKeys.showChatJoinLeave) private var showChatJoinLeave: Bool = true
    @AppStorage(AppStorageKeys.chatInputHistoryEnabled) private var chatInputHistoryEnabled: Bool = true
    @AppStorage(AppStorageKeys.notificationsEnabled) private var notificationsEnabled: Bool = true
    @AppStorage(AppStorageKeys.notifyConnected) private var notifyConnected: Bool = true
    @AppStorage(AppStorageKeys.notifyDisconnected) private var notifyDisconnected: Bool = true
    @AppStorage(AppStorageKeys.notifyPrivateMessage) private var notifyPrivateMessage: Bool = true
    @AppStorage(AppStorageKeys.notifyBroadcast) private var notifyBroadcast: Bool = true
    @AppStorage(AppStorageKeys.notifyChatInvite) private var notifyChatInvite: Bool = true
    @AppStorage(AppStorageKeys.notifyTransferFinished) private var notifyTransferFinished: Bool = true
    @AppStorage(AppStorageKeys.notifyNewsPosted) private var notifyNewsPosted: Bool = true
    @AppStorage(AppStorageKeys.dockBounceOnPrivateMessage) private var dockBounceOnPrivateMessage: Bool = true
    @AppStorage(AppStorageKeys.dockBadgeForUnreadMessages) private var dockBadgeForUnreadMessages: Bool = true
    @AppStorage(AppStorageKeys.reopenConnectionsOnLaunch) private var reopenConnectionsOnLaunch: Bool = true
    @AppStorage(AppStorageKeys.confirmBeforeDisconnect) private var confirmBeforeDisconnect: Bool = true
    @AppStorage(AppStorageKeys.useBiometricPasswordProtection) private var useBiometricPasswordProtection: Bool = false
    @AppStorage(AppStorageKeys.enableProtocolConsole) private var enableProtocolConsole: Bool = false
    @AppStorage(AppStorageKeys.contentSize)
    private var contentSizeRawValue: String = ContentSize.default.preset.rawValue
    @AppStorage(ContentSizeReader.bodyOverrideKey(for: .compact))
    private var compactBodyOverride: Double = 0
    @AppStorage(ContentSizeReader.bodyOverrideKey(for: .standard))
    private var standardBodyOverride: Double = 0
    @AppStorage(ContentSizeReader.bodyOverrideKey(for: .comfortable))
    private var comfortableBodyOverride: Double = 0

    @State private var downloadFolderPath: String = SettingsView.resolveDownloadFolder()
    @State private var showingClearConfirm = false
    @State private var notificationAuthorization: UNAuthorizationStatus = .notDetermined

    private let labelColumnWidth: CGFloat = 130
    private let outerPadding: Spacing = .medium
    private let groupSpacing: Spacing = .medium
    private let rowSpacing: Spacing = .small
    private let insidePadding: Spacing = .xsmall

    var body: some View {
        TabView {
            identityTab
                .tabItem { Label("Identity", systemImage: "person.crop.circle") }

            appearanceTab
                .tabItem { Label("Appearance", systemImage: "textformat.size") }

            chatTab
                .tabItem { Label("Chat", systemImage: "bubble.left") }

            soundsTab
                .tabItem { Label("Sounds", systemImage: "speaker.wave.2") }

            notificationsTab
                .tabItem { Label("Notifications", systemImage: "bell") }

            downloadsTab
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }

            connectionTab
                .tabItem { Label("Connection", systemImage: "network") }

            developerTab
                .tabItem { Label("Developer", systemImage: "hammer") }
        }
        .frame(width: 600, height: 560)
        .commandWCloseShortcut()
    }

    // MARK: - Tabs

    private var identityTab: some View {
        tabBody {
            GroupBox {
                VStack(alignment: .leading, spacing: rowSpacing.rawValue) {
                    labeledRow("Nickname") {
                        TextField("", text: $defaultNickname)
                            .textFieldStyle(.roundedBorder)
                    }
                    labeledRow("Icon") {
                        IconPickerButton(iconID: iconBinding)
                        Spacer(minLength: 0)
                    }
                    labeledRow("Emoji") {
                        EmojiPickerButton(emoji: emojiBinding)
                        Spacer(minLength: 0)
                    }
                    labeledRow("Banner") {
                        BannerPickerButton(bannerID: bannerBinding)
                        Spacer(minLength: 0)
                    }
                }
                .padding(insidePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Default identity", systemImage: "person")
                    .font(.headline)
            }
        }
    }

    /// Density / type-size picker. Picker rows are stable — "Aa" renders at
    /// each preset's DEFAULT body size (not the override) so they don't
    /// morph as the user nudges; the +/- controls live in a fixed slot so
    /// changing preset doesn't shuffle them. The Erika preview at the
    /// bottom is the only block that tracks the live size.
    private var appearanceTab: some View {
        tabBody {
            GroupBox {
                VStack(alignment: .leading, spacing: rowSpacing.rawValue) {
                    Picker(selection: presetBinding) {
                        ForEach(Self.contentSizeChoices, id: \.preset) { choice in
                            choiceRow(choice).tag(choice.preset)
                        }
                    } label: { EmptyView() }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()

                    bodyOverrideRow
                    caption("Affects the user list, file list, chat transcript, and other written content. Settings windows themselves stay at the macOS default.")
                    contentSizePreview
                }
                .padding(insidePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Content density", systemImage: "textformat.size")
                    .font(.headline)
            }
        }
    }

    @ViewBuilder
    private func choiceRow(_ choice: ContentSizeChoice) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small.rawValue) {
            // "Aa" at the preset's DEFAULT size — stable reference that
            // doesn't morph when the override is nudged.
            Text("Aa")
                .font(.system(size: choice.preset.defaultBodyPointSize, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(choice.title)
                // System `.caption` (stable) instead of `.heidrunCaption()`
                // (env-driven) — Settings chrome must not morph with body
                // size, else +/- buttons would shift under the cursor.
                Text(choice.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, .xxsmall)
    }

    /// Fixed "Body size: − 13pt + Reset" row that always targets the
    /// currently-selected preset. Lives outside the radio rows so switching
    /// preset doesn't shuffle controls. Reset stays present-but-disabled
    /// when no override is set so a rapid second `+` can't land on it.
    private var bodyOverrideRow: some View {
        let preset = selectedPreset
        let current = resolvedBodySize(for: preset)
        let range = ContentSize.bodyPointSizeRange
        let isOverridden = bodyOverride(for: preset) > 0
        return HStack(spacing: Spacing.xsmall.rawValue) {
            Text("Body size")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button { setBodyOverride(current - 1, for: preset) }
                label: { stepperGlyph("minus") }
                .buttonStyle(.borderless)
                .disabled(current <= range.lowerBound)
                .help("Smaller body text")
            Text(verbatim: "\(Int(current))pt")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(minWidth: 32, alignment: .center)
            Button { setBodyOverride(current + 1, for: preset) }
                label: { stepperGlyph("plus") }
                .buttonStyle(.borderless)
                .disabled(current >= range.upperBound)
                .help("Larger body text")
            Button { setBodyOverride(0, for: preset) }
                label: { stepperGlyph("arrow.counterclockwise.circle") }
                .buttonStyle(.borderless)
                .disabled(!isOverridden)
                .help("Restore the preset's built-in body size")
            Spacer(minLength: 0)
        }
        .padding(.leading, .xsmall)
    }

    /// 22×22pt hit target. `contentShape` extends the gesture region to
    /// the full frame so taps don't need to land on stroke pixels.
    private func stepperGlyph(_ name: String) -> some View {
        Image(systemName: name)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
    }

    private var presetBinding: Binding<ContentSize.Preset> {
        Binding(
            get: { ContentSize.Preset(rawValue: contentSizeRawValue) ?? .standard },
            set: { contentSizeRawValue = $0.rawValue }
        )
    }
    private var selectedPreset: ContentSize.Preset {
        ContentSize.Preset(rawValue: contentSizeRawValue) ?? .standard
    }
    private func resolvedBodySize(for preset: ContentSize.Preset) -> CGFloat {
        let override = bodyOverride(for: preset)
        return override > 0 ? CGFloat(override) : preset.defaultBodyPointSize
    }
    private func bodyOverride(for preset: ContentSize.Preset) -> Double {
        switch preset {
        case .compact:
            return compactBodyOverride
        case .standard:
            return standardBodyOverride
        case .comfortable:
            return comfortableBodyOverride
        }
    }
    private func setBodyOverride(_ value: CGFloat, for preset: ContentSize.Preset) {
        let clamped: Double
        if value <= 0 {
            clamped = 0
        } else {
            clamped = Double(min(
                max(value, ContentSize.bodyPointSizeRange.lowerBound),
                ContentSize.bodyPointSizeRange.upperBound
            ))
        }
        switch preset {
        case .compact:
            compactBodyOverride = clamped
        case .standard:
            standardBodyOverride = clamped
        case .comfortable:
            comfortableBodyOverride = clamped
        }
    }

    private struct ContentSizeChoice {
        let preset: ContentSize.Preset
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
    }
    private static let contentSizeChoices: [ContentSizeChoice] = [
        ContentSizeChoice(preset: .compact, title: "Compact", subtitle: "Smaller text, tighter rows"),
        ContentSizeChoice(preset: .standard, title: "Standard", subtitle: "The default macOS size"),
        ContentSizeChoice(preset: .comfortable, title: "Comfortable", subtitle: "Bigger text, roomier rows")
    ]

    @ViewBuilder
    private var contentSizePreview: some View {
        Divider()
        VStack(alignment: .leading, spacing: Spacing.xxsmall.rawValue) {
            Text("Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            // Trailing Spacer pins the HStack to full width so the chat
            // line's pill stays rectangular as text grows.
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xsmall.rawValue) {
                Image(systemName: "bubble.left.fill").foregroundStyle(.tint)
                Text("Erika: Welcome to Heidrun.")
                    .heidrunBody()
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            Text("12:34")
                .heidrunCaption()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.xsmall)
        .background(
            RoundedRectangle(cornerRadius: .cornerMed, style: .continuous)
                .fill(.background.secondary)
        )
    }

    private var chatTab: some View {
        tabBody {
            GroupBox {
                VStack(alignment: .leading, spacing: rowSpacing.rawValue) {
                    Toggle("Show timestamps before each message", isOn: $showChatTimestamps)
                    caption("Renders the time of day in italics right before the message body.")
                }
                .padding(insidePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Timestamps", systemImage: "clock")
                    .font(.headline)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: rowSpacing.rawValue) {
                    Toggle("Show join / leave notifications", isOn: $showChatJoinLeave)
                    caption("Adds a system line in public chat when someone connects or disconnects.")
                }
                .padding(insidePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Notifications", systemImage: "bell")
                    .font(.headline)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: rowSpacing.rawValue) {
                    Toggle("Remember recently sent messages", isOn: $chatInputHistoryEnabled)
                    caption("Press \u{2191} in the chat input to recall earlier messages, plus a recent-messages menu by the Send button. Kept in memory only and cleared when you disconnect.")
                }
                .padding(insidePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Input history", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
            }
        }
    }

    private var soundsTab: some View {
        tabBody {
            GroupBox {
                VStack(alignment: .leading, spacing: rowSpacing.rawValue) {
                    Toggle("Play sound effects", isOn: $soundsEnabled)
                    caption("Cues for chat lines, private messages, news posts, and login/logout.")
                }
                .padding(insidePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Playback", systemImage: "speaker.wave.2")
                    .font(.headline)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: Spacing.xsmall.rawValue) {
                    ForEach(SoundCue.allCases, id: \.self) { cue in
                        HStack {
                            Text(cue.resourceName)
                                .font(.body.monospaced())
                            Spacer()
                            Button("Play") { SoundPlayer.shared.play(cue) }
                                .disabled(!soundsEnabled)
                        }
                    }
                }
                .padding(insidePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Preview", systemImage: "play.circle")
                    .font(.headline)
            }
        }
    }

    private var notificationsTab: some View {
        tabBody {
            GroupBox {
                VStack(alignment: .leading, spacing: rowSpacing.rawValue) {
                    Toggle("Show system notifications", isOn: $notificationsEnabled)
                    authorizationCaption
                }
                .padding(insidePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("System notifications", systemImage: "bell")
                    .font(.headline)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: rowSpacing.rawValue) {
                    Toggle("Connected to server", isOn: $notifyConnected)
                    Toggle("Disconnected from server", isOn: $notifyDisconnected)
                    Toggle("Private message", isOn: $notifyPrivateMessage)
                    Toggle("Server broadcast", isOn: $notifyBroadcast)
                    Toggle("Private chat invitation", isOn: $notifyChatInvite)
                    Toggle("Download or upload finished", isOn: $notifyTransferFinished)
                    Toggle("News posted", isOn: $notifyNewsPosted)
                }
                .padding(insidePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(!notificationsEnabled)
            } label: {
                Label("Notify me about", systemImage: "checklist")
                    .font(.headline)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: rowSpacing.rawValue) {
                    Toggle("Bounce the dock on a new private message", isOn: $dockBounceOnPrivateMessage)
                    Toggle("Show unread message count on the dock icon", isOn: $dockBadgeForUnreadMessages)
                }
                .padding(insidePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Dock attention", systemImage: "app.badge")
                    .font(.headline)
            }
        }
        .task { await refreshAuthorizationStatus() }
    }

    @ViewBuilder
    private var authorizationCaption: some View {
        switch notificationAuthorization {
        case .denied:
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xsmall.rawValue) {
                caption("Notifications are blocked in System Settings. Heidrun will stay silent until you allow them.")
                Button("Open System Settings") { openNotificationSettings() }
                    .buttonStyle(.link)
            }
        case .notDetermined:
            caption("macOS will ask for permission the first time a notification needs to fire.")
        case .authorized, .provisional, .ephemeral:
            caption("Cues for connect, disconnect, private messages, invites, transfers, and news.")
        @unknown default:
            caption("Cues for connect, disconnect, private messages, invites, transfers, and news.")
        }
    }

    private func refreshAuthorizationStatus() async {
        notificationAuthorization = await NotificationCenterService.shared.authorizationStatusForDisplay()
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")
        else { return }
        NSWorkspace.shared.open(url)
    }

    private var downloadsTab: some View {
        tabBody {
            GroupBox {
                VStack(alignment: .leading, spacing: rowSpacing.rawValue) {
                    labeledRow("Folder", alignment: .leading, labelWidth: 50) {
                        Text(downloadFolderPath)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        Button("…") { pickDownloadFolder() }
                    }
                    caption("Files downloaded from Hotline servers land here.")
                }
                .padding(insidePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Download folder", systemImage: "arrow.down.circle")
                    .font(.headline)
            }
        }
    }

    private var connectionTab: some View {
        tabBody {
            GroupBox {
                VStack(alignment: .leading, spacing: rowSpacing.rawValue) {
                    labeledRow("Default port") {
                        Text(verbatim: defaultPort.formatted(.number.grouping(.never)))
                            .monospacedDigit()
                            .frame(minWidth: 48, alignment: .trailing)
                        Stepper("", value: $defaultPort, in: 1...65535)
                            .labelsHidden()
                        Spacer(minLength: 0)
                    }
                    Toggle("Remember recent servers", isOn: $rememberRecents)
                        .onChange(of: rememberRecents) { _, newValue in
                            if !newValue { showingClearConfirm = true }
                        }
                    Toggle(
                        "Reopen previous connections on launch",
                        isOn: $reopenConnectionsOnLaunch
                    )
                    caption("Servers you were connected to at quit are reopened the next time Heidrun starts — one window per server.")
                    Toggle(
                        "Warn before closing a connected window or quitting",
                        isOn: $confirmBeforeDisconnect
                    )
                    caption("Asks for confirmation whenever closing a window or quitting Heidrun would disconnect you from a server.")
                }
                .padding(insidePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Server defaults", systemImage: "server.rack")
                    .font(.headline)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: rowSpacing.rawValue) {
                    Toggle(
                        "Require Touch ID for saved passwords",
                        isOn: $useBiometricPasswordProtection
                    )
                    .disabled(!KeychainPasswordStore.isBiometricAvailable)
                    .onChange(of: useBiometricPasswordProtection, initial: true) { _, newValue in
                        // Re-assert on mount in case another module wrote
                        // the flag after `HeidrunMainApp.init` set it.
                        KeychainPasswordStore.useBiometricACL = newValue
                    }
                    if KeychainPasswordStore.isBiometricAvailable {
                        caption("Each server's saved password is unlocked with Touch ID once per app launch — auto-reconnect cycles re-use the unlocked value.")
                    } else {
                        caption("This Mac doesn't expose Touch ID or a paired Apple Watch. Saved passwords stay accessible via the regular keychain.")
                    }
                }
                .padding(insidePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Security", systemImage: "lock")
                    .font(.headline)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: rowSpacing.rawValue) {
                    Toggle(
                        "Automatically reconnect after an unexpected disconnect",
                        isOn: $autoReconnectEnabled
                    )
                    labeledRow("Try up to") {
                        Text(verbatim: autoReconnectMaxAttempts.formatted(.number.grouping(.never)))
                            .monospacedDigit()
                            .frame(minWidth: 36, alignment: .trailing)
                        Stepper("", value: $autoReconnectMaxAttempts, in: 1...20)
                            .labelsHidden()
                        Text("times")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .disabled(!autoReconnectEnabled)
                    labeledRow("Wait") {
                        Text(verbatim: autoReconnectDelaySeconds.formatted(.number.grouping(.never)))
                            .monospacedDigit()
                            .frame(minWidth: 36, alignment: .trailing)
                        Stepper("", value: $autoReconnectDelaySeconds, in: 1...120)
                            .labelsHidden()
                        Text("seconds between attempts")
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                    }
                    .disabled(!autoReconnectEnabled)
                    caption("Only retries when the connection drops mid-session. Server kicks and login failures are never retried.")
                }
                .padding(insidePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Auto-reconnect", systemImage: "arrow.clockwise")
                    .font(.headline)
            }
        }
        .confirmationDialog(
            "Clear stored recent servers?",
            isPresented: $showingClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                RecentsRegistry.shared.clear()
            }
            Button("Keep", role: .cancel) { rememberRecents = true }
        }
    }

    /// Hidden developer panel. Same toggle controls Window → Protocol
    /// Console visibility and whether new connections attach the
    /// `PacketObserver` that funnels every wire transaction into the
    /// console store.
    private var developerTab: some View {
        tabBody {
            GroupBox {
                VStack(alignment: .leading, spacing: rowSpacing.rawValue) {
                    Toggle(
                        "Enable protocol console",
                        isOn: $enableProtocolConsole
                    )
                    caption("Adds a Window → Protocol Console item that shows every Hotline transaction sent to and received from any open connection. Unknown transaction IDs are flagged red — useful for spotting non-standard server dialects. New connections opened after this toggle is changed pick up the new state.")
                }
                .padding(insidePadding)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Protocol Console", systemImage: "terminal")
                    .font(.headline)
            }
        }
    }

    // MARK: - Layout helpers

    /// ScrollView so a tab that grows past the fixed window height (e.g.
    /// Connection with long localized captions) stays usable.
    @ViewBuilder
    private func tabBody<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: groupSpacing.rawValue) {
                content()
            }
            .padding(outerPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private func labeledRow<Content: View>(
        _ label: LocalizedStringKey,
        alignment: Alignment = .trailing,
        labelWidth: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small.rawValue) {
            Text(label)
                .frame(
                    width: (labelWidth == nil) ? labelColumnWidth : labelWidth,
                    alignment: alignment
                )
                .foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder
    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Picking an icon fans the new identity to every live connection via
    /// TX 304 and clears the emoji slot.
    private var iconBinding: Binding<UInt16> {
        Binding(
            get: { UInt16(clamping: defaultIconID) },
            set: { newID in
                defaultIconID = Int(newID)
                // Clear via the explicit suite — see `emojiBinding` for
                // why @AppStorage writes to defaultEmoji swallow silently
                // through captured-binding chains.
                AppDataEnvironment.defaults.set(
                    "", forKey: AppStorageKeys.defaultEmoji
                )
                defaultEmoji = ""
                ActiveConnections.shared.broadcastSelfIdentity(icon: newID, emoji: nil)
            }
        )
    }

    /// Picks an emoji and fans it out via TX 304.
    ///
    /// Writes go through `AppDataEnvironment.defaults.set` directly
    /// instead of the `@AppStorage` projected binding (or a
    /// `defaultEmoji = newEmoji` assignment). Both `@AppStorage` paths
    /// silently swallowed the String write through this popover's
    /// captured-binding chain — plist showed nickname/iconID/bannerID
    /// persisted but no `Heidrun.defaultEmoji`, even after the in-line
    /// broadcast had clearly fired (server saw the new avatar). The
    /// follow-up `defaultEmoji = newEmoji` assignment is a best-effort
    /// SwiftUI invalidation so the UI repaints without waiting for the
    /// next read.
    private var emojiBinding: Binding<String> {
        Binding(
            get: { defaultEmoji },
            set: { newEmoji in
                AppDataEnvironment.defaults.set(
                    newEmoji, forKey: AppStorageKeys.defaultEmoji
                )
                defaultEmoji = newEmoji
                ActiveConnections.shared.broadcastSelfIdentity(
                    icon: UInt16(clamping: defaultIconID),
                    emoji: newEmoji.isEmpty ? nil : newEmoji
                )
            }
        )
    }

    /// Local-only banner ID — never broadcast over the wire.
    private var bannerBinding: Binding<UInt16> {
        Binding(
            get: { UInt16(clamping: defaultBannerID) },
            set: { defaultBannerID = Int($0) }
        )
    }

    // MARK: - Download folder picker

    private func pickDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: AppStorageKeys.downloadFolderBookmark)
            downloadFolderPath = url.path
        } catch {
            downloadFolderPath = url.path
        }
    }

    static func resolveDownloadFolder() -> String {
        if let data = UserDefaults.standard.data(forKey: AppStorageKeys.downloadFolderBookmark) {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                // Once we adopt the sandbox entitlement, file IO through
                // this URL will need to bracket with
                // start/stopAccessingSecurityScopedResource().
                return url.path
            }
        }
        let fallback = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        return fallback?.path ?? "~/Downloads"
    }
}
