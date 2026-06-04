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
    @State private var confirmDeleteAll = false

    public init(viewModel: MessagesViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        HSplitView {
            threadList
                // Width clamped via min/max; the actual position
                // persists across launches via the autosaver below.
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 360)
                .background(SplitViewAutosaver(name: "Heidrun.messages.threads"))
            detail
                .frame(minWidth: 320)
        }
        .padding(.bottom, .xlarge)
        .confirmationDialog(
            "Delete all conversations?",
            isPresented: $confirmDeleteAll
        ) {
            Button("Delete All", role: .destructive) {
                viewModel.deleteAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every conversation in this list will be cleared. Hotline doesn't persist private messages server-side, so this is local only.")
        }
    }

    // MARK: - Thread list

    private var threadList: some View {
        VStack(spacing: 0) {
            breadcrumb

            Divider()

            if viewModel.threads.isEmpty {
                emptyList
            } else {
                ConversationsTableView(
                    conversations: viewModel.threads.map { thread in
                        ConversationDisplay(
                            id: thread.id,
                            nickname: viewModel.nickname(for: thread.id),
                            iconID: viewModel.icon(for: thread.id),
                            emoji: viewModel.emoji(for: thread.id),
                            isOnline: viewModel.isOnline(socket: thread.id),
                            hasUnread: thread.hasUnread,
                            lastMessagePreview: thread.messages.last?.text
                        )
                    },
                    selectedID: viewModel.activeThreadID,
                    onSelect: { socket in viewModel.openThread(with: socket) },
                    onDelete: { socket in viewModel.deleteConversation(socket: socket) },
                    transcriptText: { socket in viewModel.transcript(for: socket) },
                    transcriptTitle: { socket in
                        viewModel.nickname(for: socket) ?? "Conversation"
                    }
                )
            }
        }
        .background(.background)
    }

    /// Unified breadcrumb-style header matching the news pane: a label,
    /// the conversation counter, and per-list actions on the trailing
    /// edge. 24pt content height like the other modules.
    private var breadcrumb: some View {
        GroupBox {
            HStack(alignment: .center, spacing: Spacing.xxsmall.rawValue) {
                Image(systemName: "envelope")
                    .resizable()
                    .scaledToFit()
                    .font(.subheadline)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
                Text("Conversations")
                    .heidrunBody()
                    .foregroundStyle(.primary)
                if !viewModel.threads.isEmpty {
                    Text(verbatim: "(\(viewModel.threads.count))")
                        .heidrunCaption()
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer()

                ActionButton(
                    title: "Delete Conversation",
                    systemImage: "trash",
                    isEnabled: viewModel.activeThreadID != nil,
                    role: .destructive,
                    size: .small,
                    fontWeight: .light
                ) {
                    if let socket = viewModel.activeThreadID {
                        viewModel.deleteConversation(socket: socket)
                    }
                }

                ActionButton(
                    title: "Delete All",
                    systemImage: "trash.slash",
                    isEnabled: !viewModel.threads.isEmpty,
                    role: .destructive,
                    size: .small,
                    fontWeight: .light
                ) {
                    confirmDeleteAll = true
                }
            }
            .font(.subheadline)
            .padding(.horizontal, .xsmall)
            .frame(height: 24)
        }
        .background(.background)
        .padding(.horizontal, .xsmall)
        .padding(.vertical, .xxxsmall)
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

// MARK: - Detail

private struct ThreadDetail: View {
    let thread: MessagesViewModel.Thread
    let nickname: String
    let iconID: UInt16?
    let emoji: String?
    let isOnline: Bool
    @Binding var draft: String
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

    /// Mirrors the left-pane breadcrumb: GroupBox + 24pt content height
    /// + matching outer paddings, so the divider between the conversation
    /// list and the detail pane lands on the same baseline.
    private var header: some View {
        GroupBox {
            HStack(alignment: .center, spacing: Spacing.xxsmall.rawValue) {
                UserIcon(id: iconID, emoji: emoji, size: 20)
                    .opacity(isOnline ? 1.0 : 0.4)
                Text(nickname)
                    .heidrunBody()
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(verbatim: "·")
                    .foregroundStyle(.tertiary)
                Text(isOnline ? "online" : "offline")
                    .heidrunCaption()
                    .foregroundStyle(isOnline ? .secondary : .tertiary)
                Spacer()
            }
            .font(.subheadline)
            .padding(.horizontal, .xsmall)
            .frame(height: 24)
        }
        .background(.background)
        .padding(.horizontal, .xsmall)
        .padding(.vertical, .xxxsmall)
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

    /// Composer mirrors the chat input — `IsolatedTextEditor` so typing
    /// doesn't dirty the enclosing DocumentGroup bookmark, with ⌘↵
    /// wired to send. `autoFocus` matches chat: ready to type when the
    /// thread opens (only if the correspondent is online).
    private var inputRow: some View {
        HStack(alignment: .top, spacing: Spacing.xsmall.rawValue) {
            IsolatedTextEditor(
                text: $draft,
                minHeight: 50,
                autoFocus: isOnline,
                onSubmit: { if isOnline { onSend() } }
            )
            .frame(height: 50)
            .padding(.horizontal, .xxsmall)
            .padding(.vertical, .xsmall)
            .background(.background)
            .overlay(
                RoundedRectangle(cornerRadius: .cornerMed, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: .cornerMed, style: .continuous))

            Button("Send", action: onSend)
                .padding(.top, .xxsmall)
                .disabled(isDraftEmpty || !isOnline)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Send message \u{2318}+\u{23CE}")
        }
        .padding(.horizontal, .xsmall)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var isDraftEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
