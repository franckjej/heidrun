import Foundation
import Testing
@testable import HeidrunMessages
import HeidrunCore

@Suite("MessagesViewModel")
struct MessagesViewModelTests {
    @Test("incoming messages create a thread per remote user")
    @MainActor
    func incomingCreatesThread() async {
        let (events, continuation) = AsyncStream<HotlineEvent>.makeStream()
        let viewModel = MessagesViewModel(events: events, sendMessage: { _, _ in })

        let observation = Task { await viewModel.observe() }
        continuation.yield(.messageReceived(from: 7, message: "hi"))
        continuation.yield(.messageReceived(from: 9, message: "hello"))
        continuation.yield(.messageReceived(from: 7, message: "again"))
        continuation.finish()
        await observation.value

        let socketsInRecencyOrder = viewModel.threads.map(\.id)
        // Most recent activity goes to the front: thread 7 wins because it
        // got the last message; thread 9 follows.
        #expect(socketsInRecencyOrder == [7, 9])
        let sevenThread = viewModel.threads.first { $0.id == 7 }!
        #expect(sevenThread.messages.map(\.text) == ["hi", "again"])
        #expect(sevenThread.hasUnread)
    }

    @Test("active thread does not get marked unread when its messages arrive")
    @MainActor
    func activeThreadStaysRead() async {
        let (events, continuation) = AsyncStream<HotlineEvent>.makeStream()
        let viewModel = MessagesViewModel(events: events, sendMessage: { _, _ in })

        viewModel.openThread(with: 7)

        let observation = Task { await viewModel.observe() }
        continuation.yield(.messageReceived(from: 7, message: "while reading"))
        continuation.finish()
        await observation.value

        let thread = viewModel.threads.first { $0.id == 7 }!
        #expect(!thread.hasUnread)
    }

    @Test("sendDraft sends to the active thread, appends locally, clears draft")
    @MainActor
    func sendDraftAppendsLocally() async throws {
        let (events, _) = AsyncStream<HotlineEvent>.makeStream()
        let recorder = MessageRecorder()
        let viewModel = MessagesViewModel(
            events: events,
            sendMessage: { message, socket in
                await recorder.record(message: message, socket: socket)
            }
        )

        viewModel.openThread(with: 42)
        viewModel.draft = "  hey  "
        try await viewModel.sendDraft()

        let calls = await recorder.calls
        #expect(calls.count == 1)
        #expect(calls.first?.message == "hey")
        #expect(calls.first?.socket == 42)
        #expect(viewModel.draft.isEmpty)

        let thread = viewModel.threads.first!
        #expect(thread.messages.map(\.text) == ["hey"])
        #expect(thread.messages.first?.direction == .outgoing)
    }

    @Test("sendDraft is a no-op when nothing is selected")
    @MainActor
    func sendDraftSkipsWithoutSelection() async throws {
        let (events, _) = AsyncStream<HotlineEvent>.makeStream()
        let recorder = MessageRecorder()
        let viewModel = MessagesViewModel(
            events: events,
            sendMessage: { message, socket in
                await recorder.record(message: message, socket: socket)
            }
        )
        viewModel.draft = "hey"
        try await viewModel.sendDraft()

        let calls = await recorder.calls
        #expect(calls.isEmpty)
    }
}

@Suite("MessagesFeature")
struct MessagesFeatureTests {
    @Test("static metadata is stable")
    func metadata() {
        #expect(MessagesFeature.identifier  == "com.heidrun.messages")
        #expect(MessagesFeature.displayName == "Messages")
        #expect(!MessagesFeature.systemImage.isEmpty)
    }
}

private actor MessageRecorder {
    struct Call: Sendable, Hashable {
        let message: String
        let socket: UInt16
    }
    private(set) var calls: [Call] = []
    func record(message: String, socket: UInt16) {
        calls.append(Call(message: message, socket: socket))
    }
}
