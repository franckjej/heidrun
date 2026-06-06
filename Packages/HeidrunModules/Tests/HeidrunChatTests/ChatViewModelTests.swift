import Foundation
import Testing
@testable import HeidrunChat
import HeidrunCore

@Suite("ChatViewModel")
struct ChatViewModelTests {
    @Test("public chat scope collects only public chat lines")
    @MainActor
    func publicScopeFiltersPrivateLines() async {
        let (events, continuation) = AsyncStream<HotlineEvent>.makeStream()
        let viewModel = ChatViewModel(
            events: events,
            sendChat: { _, _, _ in },
            chatScope: nil
        )

        let observation = Task { await viewModel.observe() }

        continuation.yield(.chatReceived(chat: nil, message: "hi", isAction: false))
        continuation.yield(.chatReceived(chat: ChatID(rawValue: 1), message: "private", isAction: false))
        continuation.yield(.chatReceived(chat: nil, message: "world", isAction: true))
        continuation.finish()

        await observation.value

        #expect(viewModel.lines.count == 2)
        #expect(viewModel.lines.map(\.body) == ["hi", "world"])
        #expect(viewModel.lines[1].isAction)
    }

    @Test("private chat scope collects only matching room lines")
    @MainActor
    func privateScopeFiltersOtherRooms() async {
        let room = ChatID(rawValue: 0xCAFE)
        let other = ChatID(rawValue: 0xBEEF)

        let (events, continuation) = AsyncStream<HotlineEvent>.makeStream()
        let viewModel = ChatViewModel(
            events: events,
            sendChat: { _, _, _ in },
            chatScope: room
        )
        let observation = Task { await viewModel.observe() }

        continuation.yield(.chatReceived(chat: room, message: "in", isAction: false))
        continuation.yield(.chatReceived(chat: other, message: "out", isAction: false))
        continuation.yield(.chatReceived(chat: nil, message: "pub", isAction: false))
        continuation.finish()

        await observation.value

        #expect(viewModel.lines.map(\.body) == ["in"])
    }

    @Test("public chat scope applies a Chat-ID-0 subject (the server topic)")
    @MainActor
    func publicScopeAppliesPublicSubject() async {
        let (events, continuation) = AsyncStream<HotlineEvent>.makeStream()
        let viewModel = ChatViewModel(
            events: events,
            sendChat: { _, _, _ in },
            chatScope: nil
        )
        let observation = Task { await viewModel.observe() }

        continuation.yield(.privateChatSubjectChanged(chat: ChatID(rawValue: 0), subject: "Welcome"))
        continuation.finish()
        await observation.value

        #expect(viewModel.subject == "Welcome")
    }

    @Test("public chat scope ignores a private room's subject")
    @MainActor
    func publicScopeIgnoresPrivateSubject() async {
        let (events, continuation) = AsyncStream<HotlineEvent>.makeStream()
        let viewModel = ChatViewModel(
            events: events,
            sendChat: { _, _, _ in },
            chatScope: nil
        )
        let observation = Task { await viewModel.observe() }

        continuation.yield(.privateChatSubjectChanged(chat: ChatID(rawValue: 0xCAFE), subject: "secret"))
        continuation.finish()
        await observation.value

        #expect(viewModel.subject.isEmpty)
    }

    @Test("sendDraft trims whitespace and clears the draft")
    @MainActor
    func sendDraftTrimsAndClears() async throws {
        let (events, _) = AsyncStream<HotlineEvent>.makeStream()
        let recorder = ChatRecorder()
        let viewModel = ChatViewModel(
            events: events,
            sendChat: { message, chat, action in
                await recorder.record(message: message, chat: chat, isAction: action)
            },
            chatScope: nil
        )

        viewModel.draft = "  hi  "
        try await viewModel.sendDraft()

        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls.first?.message == "hi")
        #expect(viewModel.draft.isEmpty)
    }

    @Test("sendDraft is a no-op when the draft is whitespace-only")
    @MainActor
    func sendDraftSkipsBlank() async throws {
        let (events, _) = AsyncStream<HotlineEvent>.makeStream()
        let recorder = ChatRecorder()
        let viewModel = ChatViewModel(
            events: events,
            sendChat: { message, chat, action in
                await recorder.record(message: message, chat: chat, isAction: action)
            },
            chatScope: nil
        )

        viewModel.draft = "   \n  "
        try await viewModel.sendDraft()

        let calls = await recorder.calls
        #expect(calls.isEmpty)
    }

    @Test("clearLines wipes prior lines and leaves a single system trace")
    @MainActor
    func clearLinesLeavesSystemTrace() async {
        let (events, continuation) = AsyncStream<HotlineEvent>.makeStream()
        let viewModel = ChatViewModel(
            events: events,
            sendChat: { _, _, _ in },
            chatScope: nil
        )
        let observation = Task { await viewModel.observe() }

        continuation.yield(.chatReceived(chat: nil, message: "alpha", isAction: false))
        continuation.yield(.chatReceived(chat: nil, message: "beta", isAction: false))
        continuation.finish()
        await observation.value

        #expect(viewModel.lines.count == 2)

        viewModel.clearLines()

        #expect(viewModel.lines.count == 1)
        #expect(viewModel.lines[0].isSystem)
        #expect(viewModel.lines[0].sender == nil)
        #expect(viewModel.lines[0].body.contains("Chat cleared"))
    }

    @Test("sendDraft treats /clear as a local command, never calls sendChat")
    @MainActor
    func sendDraftClearDoesNotCallSendChat() async throws {
        let (events, _) = AsyncStream<HotlineEvent>.makeStream()
        let recorder = ChatRecorder()
        let viewModel = ChatViewModel(
            events: events,
            sendChat: { message, chat, action in
                await recorder.record(message: message, chat: chat, isAction: action)
            },
            chatScope: nil
        )

        viewModel.draft = "/clear"
        try await viewModel.sendDraft()

        let calls = await recorder.calls
        #expect(calls.isEmpty)
        #expect(viewModel.draft.isEmpty)
        #expect(viewModel.lines.count == 1)
        #expect(viewModel.lines[0].isSystem)
        #expect(viewModel.lines[0].body.contains("Chat cleared"))
    }

    @Test("sendDraft /clear wipes pre-existing lines and leaves the trace")
    @MainActor
    func sendDraftClearWipesExistingLines() async throws {
        let (events, continuation) = AsyncStream<HotlineEvent>.makeStream()
        let viewModel = ChatViewModel(
            events: events,
            sendChat: { _, _, _ in },
            chatScope: nil
        )
        let observation = Task { await viewModel.observe() }
        continuation.yield(.chatReceived(chat: nil, message: "alpha", isAction: false))
        continuation.yield(.chatReceived(chat: nil, message: "beta", isAction: false))
        continuation.finish()
        await observation.value

        viewModel.draft = "/clear"
        try await viewModel.sendDraft()

        #expect(viewModel.lines.count == 1)
        #expect(viewModel.lines[0].isSystem)
        #expect(viewModel.lines[0].body.contains("Chat cleared"))
    }

    @Test("sendDraft treats whitespace-padded /clear as the command")
    @MainActor
    func sendDraftClearAcceptsWhitespace() async throws {
        let (events, _) = AsyncStream<HotlineEvent>.makeStream()
        let recorder = ChatRecorder()
        let viewModel = ChatViewModel(
            events: events,
            sendChat: { message, chat, action in
                await recorder.record(message: message, chat: chat, isAction: action)
            },
            chatScope: nil
        )

        viewModel.draft = "  /clear  "
        try await viewModel.sendDraft()

        let calls = await recorder.calls
        #expect(calls.isEmpty)
        #expect(viewModel.lines.count == 1)
        #expect(viewModel.lines[0].isSystem)
    }

    @Test("sendDraft /CLEAR is case-insensitive")
    @MainActor
    func sendDraftClearIsCaseInsensitive() async throws {
        let (events, _) = AsyncStream<HotlineEvent>.makeStream()
        let recorder = ChatRecorder()
        let viewModel = ChatViewModel(
            events: events,
            sendChat: { message, chat, action in
                await recorder.record(message: message, chat: chat, isAction: action)
            },
            chatScope: nil
        )

        viewModel.draft = "/CLEAR"
        try await viewModel.sendDraft()

        let calls = await recorder.calls
        #expect(calls.isEmpty)
        #expect(viewModel.lines.count == 1)
        #expect(viewModel.lines[0].isSystem)
    }

    @Test("sendDraft does not trigger /clear on partial matches like /cleartext")
    @MainActor
    func sendDraftDoesNotTriggerOnPartialMatch() async throws {
        let (events, _) = AsyncStream<HotlineEvent>.makeStream()
        let recorder = ChatRecorder()
        let viewModel = ChatViewModel(
            events: events,
            sendChat: { message, chat, action in
                await recorder.record(message: message, chat: chat, isAction: action)
            },
            chatScope: nil
        )

        viewModel.draft = "/cleartext"
        try await viewModel.sendDraft()

        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls.first?.message == "/cleartext")
        #expect(calls.first?.isAction == false)
        #expect(viewModel.lines.isEmpty)
        #expect(viewModel.draft.isEmpty)
    }

    // MARK: - Input history

    @Test("sendDraft records the sent message into history, newest first")
    @MainActor
    func sendDraftRecordsHistory() async throws {
        let (events, _) = AsyncStream<HotlineEvent>.makeStream()
        let viewModel = ChatViewModel(events: events, sendChat: { _, _, _ in }, chatScope: nil)

        viewModel.draft = "hello"
        try await viewModel.sendDraft()
        viewModel.draft = "world"
        try await viewModel.sendDraft()

        #expect(viewModel.recentMessages == ["world", "hello"])
        #expect(viewModel.draft.isEmpty)
    }

    @Test("recall steps through sent history into the draft")
    @MainActor
    func recallStepsHistory() async throws {
        let (events, _) = AsyncStream<HotlineEvent>.makeStream()
        let viewModel = ChatViewModel(events: events, sendChat: { _, _, _ in }, chatScope: nil)
        viewModel.draft = "first";  try await viewModel.sendDraft()
        viewModel.draft = "second"; try await viewModel.sendDraft()

        #expect(viewModel.recallPreviousDraft() == "second")
        #expect(viewModel.draft == "second")
        #expect(viewModel.recallPreviousDraft() == "first")
        #expect(viewModel.recallNextDraft() == "second")
    }

    @Test("useRecent loads a message into the draft")
    @MainActor
    func useRecentLoadsDraft() async throws {
        let (events, _) = AsyncStream<HotlineEvent>.makeStream()
        let viewModel = ChatViewModel(events: events, sendChat: { _, _, _ in }, chatScope: nil)
        viewModel.draft = "earlier"; try await viewModel.sendDraft()
        viewModel.useRecent("earlier")
        #expect(viewModel.draft == "earlier")
    }
}

@Suite("ChatFeature")
struct ChatFeatureTests {
    @Test("static metadata is stable")
    func staticMetadata() {
        #expect(ChatFeature.identifier  == "com.heidrun.chat")
        #expect(ChatFeature.displayName == "Chat")
        #expect(!ChatFeature.systemImage.isEmpty)
    }
}

private actor ChatRecorder {
    struct Call: Sendable {
        let message: String
        let chat: ChatID?
        let isAction: Bool
    }

    private(set) var calls: [Call] = []

    func record(message: String, chat: ChatID?, isAction: Bool) {
        calls.append(Call(message: message, chat: chat, isAction: isAction))
    }
}
