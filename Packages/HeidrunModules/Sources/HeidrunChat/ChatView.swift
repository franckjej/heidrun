import SwiftUI
import HeidrunCore
import HeidrunUI
import CommonTools

/// SwiftUI surface for one chat scope (public chat or one private room).
///
/// Hosts a header bar (server name + subject), the lines list, and an
/// input row. The observation loop is owned at connection scope
/// (`ConnectionHandle`); `.onAppear` calls the idempotent
/// `viewModel.start()` as a safety net for standalone presentation.
public struct ChatView: View {
    @State private var viewModel: ChatViewModel
    // `IsolatedTextEditor`'s `autoFocus: true` handles first-responder
    // grabbing internally — no SwiftUI `@FocusState` needed.
    @State private var editingSubject: Bool = false
    @State private var subjectDraft: String = ""

    @AppStorage("Heidrun.showChatTimestamps") private var showTimestamps: Bool = false
    @AppStorage("Heidrun.showChatJoinLeave")  private var showJoinLeave: Bool = true

    public init(viewModel: ChatViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    /// Filter applied at render time so toggling join/leave on or off is
    /// instant and doesn't disturb the underlying chronological log.
    private var visibleLines: [ChatViewModel.Line] {
        showJoinLeave
            ? viewModel.lines
            : viewModel.lines.filter { !$0.isSystem }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            messageList
            Divider()
            inputRow
                .padding(.top, .xxsmall)
                .padding(.bottom, .small)
        }
        .padding(.bottom, .small)
        .frame(alignment: .topLeading)
        .onAppear {
            // Idempotent. The host (HostView) usually drives start() at
            // the connection level so the chat keeps observing while
            // the user is on another module; this is a safety net for
            // the case where a ChatViewModel is presented standalone.
            viewModel.start()
        }
        .sheet(isPresented: $editingSubject) {
            SubjectEditorSheet(
                initialText: subjectDraft,
                onSubmit: { text in
                    try? await viewModel.setSubject(text)
                    editingSubject = false
                },
                onCancel: { editingSubject = false }
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        GroupBox {
            HStack(spacing: Spacing.xxsmall.rawValue) {
                Image(systemName: "bubble.left")
                    .resizable()
                    .scaledToFit()
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                // Header title preference order:
                //   1. Server-pushed chat subject (TX 119) — the
                //      explicit topic when one exists. heidrun-server
                //      pushes this for Chat ID 0 via its `/topic`
                //      extension; vanilla Hotline servers don't.
                //   2. Bookmark name (or raw address for ad-hoc URL
                //      sessions) — gives third-party servers without
                //      a topic a recognisable identity.
                //   3. "Chat" — fallback when we have neither.
                Text(headerTitle)
                    .heidrunBody()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                    // Subject editing only meaningful for private chats — vanilla
                    // Hotline servers don't accept a subject change on public chat.
                if viewModel.chatScope != nil {
                    Button {
                        subjectDraft = viewModel.subject
                        editingSubject = true
                    } label: {
                        Image(systemName: "text.badge.plus")
                            .resizable()
                            .scaledToFit()
                            .font(.body)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .controlSize(.regular)
                    .help("Set chat subject")
                }
            }
            .font(.subheadline)
            .padding(.horizontal, .xsmall)
            .padding(.vertical, .xxxsmall)
        }
        .padding(.horizontal, .xsmall)
        .padding(.vertical, .xxsmall)
        .frame(height: 40)
        .background(.background)
    }

    /// Subject if the server pushed one; otherwise the bookmark name
    /// (or address, via ChatViewModel's resolver fallback); otherwise
    /// the generic "Chat". Pulled out so the header view stays a flat
    /// HStack and the three-step preference order is testable.
    private var headerTitle: String {
        if !viewModel.subject.isEmpty { return viewModel.subject }
        if !viewModel.serverName.isEmpty { return viewModel.serverName }
        return String(localized: "Chat")
    }

    // MARK: - Messages

    private var messageList: some View {
        SelectableTranscript(
            lines: ChatTranscriptProjection.lines(
                from: visibleLines,
                showTimestamps: showTimestamps,
                timestampFormatter: Self.timestampFormatter
            )
        )
        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
        .draggable(TextFileExport(
            fileName: transcriptFileName,
            text: ChatTranscriptFormatter.format(visibleLines)
        ))
    }

    /// File-name base for a dragged-out transcript: the subject if the
    /// (private) chat has one, else the server name, else "Chat".
    private var transcriptFileName: String {
        if !viewModel.subject.isEmpty { return viewModel.subject }
        return viewModel.serverName.isEmpty ? "Chat" : viewModel.serverName
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private var inputRow: some View {
        HStack(alignment: .top, spacing: Spacing.xsmall.rawValue) {
            // `IsolatedTextEditor` instead of `TextEditor` so typing in
            // the chat doesn't dirty the enclosing DocumentGroup
            // bookmark (and prompt "Save changes?" on close, autosave
            // to a UUID-named file, etc). ⌘↵ → submit is wired in the
            // text view so the user doesn't have to leave the input
            // to send.
            IsolatedTextEditor(
                text: $viewModel.draft,
                minHeight: 50,
                autoFocus: true,
                onSubmit: submit
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
            Button("Send", action: submit)
                .padding(.top, .xxsmall)
                .disabled(isDraftEmpty)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Send message \u{2318}+\u{23CE}")
        }
        .padding(.horizontal, .xsmall)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var isDraftEmpty: Bool {
        viewModel.draft
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    private func submit() {
        Task {
            try? await viewModel.sendDraft()
        }
    }
}

// MARK: - Subject editor

private struct SubjectEditorSheet: View {
    let initialText: String
    var onSubmit: @MainActor (String) async -> Void
    var onCancel: () -> Void

    @State private var text: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small.rawValue) {
            Text("Set Chat Subject")
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Subject", text: $text)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Set") {
                    Task { @MainActor in await onSubmit(text) }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(.small)
        .frame(minWidth: 360)
        .onAppear { text = initialText }
    }
}

extension NSTextField {
    override open var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }
}
