import SwiftUI
import HeidrunCore
import HeidrunUI
import CommonTools

/// Two-pane direct-messages surface: a fixed-width thread list on the
/// left (clamped via `HSplitView` so the user can't collapse it into the
/// edge) and the active conversation on the right. The host already
/// owns the outer `NavigationSplitView`, so this view stays flat to
/// avoid the nested-split-view layout glitches AppKit exhibits.
public struct MessagesView: View {
    @State private var viewModel: MessagesViewModel
    @FocusState private var inputFocused: Bool

    public init(viewModel: MessagesViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        HSplitView {
            threadList
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
            detail
                .frame(minWidth: 320)
        }
        .padding(.bottom, .xlarge)
    }

    // MARK: - Thread list

    private var threadList: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.xxsmall.rawValue) {
                Image(systemName: "envelope")
                    .foregroundStyle(.secondary)
                Text("Conversations")
                    .heidrunBody()
                    .foregroundStyle(.secondary)
                Spacer()
                if !viewModel.threads.isEmpty {
                    Text(verbatim: "\(viewModel.threads.count)")
                        .heidrunCaption()
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, .xsmall)
            .padding(.vertical, .xxsmall)

            Divider()

            if viewModel.threads.isEmpty {
                emptyList
            } else {
                List(selection: Binding(
                    get: { viewModel.activeThreadID },
                    set: { newValue in
                        if let id = newValue { viewModel.openThread(with: id) }
                    }
                )) {
                    ForEach(viewModel.threads) { thread in
                        ThreadRow(
                            thread: thread,
                            nickname: viewModel.nickname(for: thread.id),
                            iconID: viewModel.icon(for: thread.id),
                            emoji: viewModel.emoji(for: thread.id),
                            isOnline: viewModel.isOnline(socket: thread.id)
                        )
                        .tag(thread.id)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
        .background(.background)
    }

    private var emptyList: some View {
        ContentUnavailableView {
            Label("No conversations", systemImage: "tray")
        } description: {
            Text("Private messages from other users will show up here. Start one from the user list in Chat.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detail: some View {
        if let id = viewModel.activeThreadID,
           let thread = viewModel.threads.first(where: { $0.id == id }) {
            ThreadDetail(
                thread: thread,
                nickname: viewModel.nickname(for: id) ?? "Unknown user",
                iconID: viewModel.icon(for: id),
                emoji: viewModel.emoji(for: id),
                isOnline: viewModel.isOnline(socket: id),
                draft: $viewModel.draft,
                inputFocused: $inputFocused,
                onSend: { Task { try? await viewModel.sendDraft() } }
            )
        } else {
            ContentUnavailableView(
                "Pick a conversation",
                systemImage: "envelope.open",
                description: Text("Select a thread on the left to read and reply.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Rows

private struct ThreadRow: View {
    let thread: MessagesViewModel.Thread
    let nickname: String?
    let iconID: UInt16?
    let emoji: String?
    let isOnline: Bool

    var body: some View {
        HStack(spacing: Spacing.xsmall.rawValue) {
            UserIcon(id: iconID, emoji: emoji, size: 24)
                .opacity(isOnline ? 1.0 : 0.4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Spacing.xxsmall.rawValue) {
                    Text(nickname ?? "Unknown user")
                        .heidrunBody()
                        .fontWeight(thread.hasUnread ? .semibold : .regular)
                        .lineLimit(1)
                    if !isOnline {
                        Text("offline")
                            .heidrunCaption()
                            .foregroundStyle(.tertiary)
                    }
                }
                if let last = thread.messages.last {
                    Text(last.text)
                        .heidrunCaption()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if thread.hasUnread {
                Circle()
                    .fill(.tint)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, .tiny)
    }
}

private struct ThreadDetail: View {
    let thread: MessagesViewModel.Thread
    let nickname: String
    let iconID: UInt16?
    let emoji: String?
    let isOnline: Bool
    @Binding var draft: String
    @FocusState.Binding var inputFocused: Bool
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messages
            Divider()
            inputRow
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.xsmall.rawValue) {
            UserIcon(id: iconID, emoji: emoji, size: 28)
                .opacity(isOnline ? 1.0 : 0.4)
            VStack(alignment: .leading, spacing: 0) {
                Text(nickname)
                    .font(.headline)
                    .lineLimit(1)
                Text(isOnline ? "online" : "offline")
                    .heidrunCaption()
                    .foregroundStyle(isOnline ? .secondary : .tertiary)
            }
            Spacer()
        }
        .padding(.horizontal, .xsmall)
        .padding(.vertical, .xxsmall)
        .frame(height: 44)
        .background(.background)
    }

    private var messages: some View {
        SelectableTranscript(
            lines: MessagesTranscriptProjection.lines(
                from: thread.messages,
                ownNickname: "Me",
                peerNickname: nickname,
                timestampFormatter: Self.timestampFormatter
            )
        )
        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var inputRow: some View {
        HStack(spacing: Spacing.xsmall.rawValue) {
            TextField("Reply…", text: $draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused($inputFocused)
                .lineLimit(1...4)
                .onSubmit(onSend)
                .disabled(!isOnline)

            Button("Send", action: onSend)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isOnline)
        }
        .padding(.horizontal, .xsmall)
        .padding(.vertical, .xxsmall)
        .onAppear { inputFocused = isOnline }
    }
}

// MARK: - Helpers

/// Renders a user's emoji avatar if present, else the bundled Hotline
/// icon for `id`, falling back to an SF Symbol when the catalog has no
/// entry. Pixel-aligned so the original 16×16 / 32×32 PNGs stay crisp.
private struct UserIcon: View {
    let id: UInt16?
    var emoji: String?
    var size: CGFloat = 24

    var body: some View {
        if let emoji = EmojiAvatar.sanitized(emoji) {
            // `.fixedSize()` renders the glyph at natural size so the tall
            // emoji line box isn't clipped by the square frame (matches the
            // roster avatar).
            Text(emoji)
                .font(.system(size: size * 0.85))
                .fixedSize()
                .frame(width: size, height: size)
        } else if let id, let cg = IconCatalog.shared.icons.cgImage(forID: Int(id)) {
            Image(decorative: cg, scale: 1, orientation: .up)
                .interpolation(.none)
                .resizable()
                .frame(width: size, height: size)
        } else {
            Image(systemName: "person.crop.square")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }
}
