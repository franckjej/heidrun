import SwiftUI
import HeidrunCore
import HeidrunUI
import CommonTools

/// Read-only modal showing extended profile info for a single user. The
/// caller provides the fetch closure; the sheet handles loading / error /
/// retry / display states internally.
public struct UserInfoSheet: View {
    public let nickname: String
    /// Numeric icon ID used to look up the header thumbnail in the
    /// bundled icon catalog. Pass `nil` when the caller has no iconID
    /// yet (e.g. opening this from a Tracker row); the header falls
    /// back to a generic SF Symbol.
    public let iconID: Int?
    /// Optional emoji avatar (Heidrun extension); when present it renders
    /// in the header instead of the numeric icon, matching the roster.
    public let emoji: String?
    public let fetch: () async throws -> UserInfo
    public let onDismiss: () -> Void

    @State private var info: UserInfo?
    @State private var error: String?
    @State private var loading: Bool = true

    public init(
        nickname: String,
        iconID: Int? = nil,
        emoji: String? = nil,
        fetch: @escaping () async throws -> UserInfo,
        onDismiss: @escaping () -> Void
    ) {
        self.nickname = nickname
        self.iconID = iconID
        self.emoji = emoji
        self.fetch = fetch
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                headerIcon
                Text("Info for \(nickname)")
                    .font(.headline)
            }

            content

            HStack {
                Spacer()
                Button("Done", action: onDismiss)
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.medium)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 420, idealHeight: 480)
        .closeOnCmdW(onDismiss)
        .task { await load() }
    }

    @ViewBuilder
    private var headerIcon: some View {
        if let emoji = EmojiAvatar.sanitized(emoji) {
            Text(emoji)
                .font(.system(size: 27))
                .fixedSize()
                .frame(width: 32, height: 32)
        } else if let iconID, let cgImage = IconCatalog.shared.icons.cgImage(forID: iconID) {
            Image(decorative: cgImage, scale: 1, orientation: .up)
                .interpolation(.none)
                .resizable()
                .frame(width: 32, height: 32)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 32, height: 32)
                .symbolRenderingMode(.hierarchical)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            VStack { Spacer(); ProgressView(); Spacer() }
                .frame(maxWidth: .infinity)
        } else if let error {
            VStack(alignment: .leading, spacing: 8) {
                Text("Couldn't load info: \(error)")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                Button("Retry") { Task { await load() } }
            }
        } else if let info {
            VStack(alignment: .leading, spacing: 6) {
                row("Account", info.accountLogin.isEmpty ? "—" : info.accountLogin)
                row("Socket", "\(info.user.socket)")
                row("Status", info.user.status.flags.displayLabel)
                Divider()
                Text("Profile")
                    .font(.subheadline.bold())
                profileScrollView(text: info.infoText)
            }
        }
    }

    /// Scrollable, read-only, monospaced view of the server's free-form
    /// profile text (field 101). `TextEditor` with `.disabled(true)`
    /// stops scrolling on macOS, so we use a `ScrollView` + `Text` pair
    /// that keeps selection (handy for copying an address out of the
    /// profile dump some servers send). Flexes to fill whatever vertical
    /// space the sheet has left after the metadata rows.
    @ViewBuilder
    private func profileScrollView(text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.xsmall)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(.separator)
        )
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(label):")
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            info = try await fetch()
            loading = false
        } catch {
            self.error = String(describing: error)
            loading = false
        }
    }
}
