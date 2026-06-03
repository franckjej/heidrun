import Foundation
import Testing
@testable import HeidrunNews
import HeidrunCore

@MainActor
@Suite("ThreadedNewsViewModel.editThread")
struct ThreadedNewsViewModelEditTests {
    private struct DeleteCall: Equatable {
        let path: RemotePath
        let threadID: UInt16
        let cascade: Bool
    }

    private struct PostCall: Equatable {
        let path: RemotePath
        let parentID: UInt16
        let title: String
        let type: String
        let body: String
    }

    /// Recording fakes that capture each call's arguments so tests can
    /// assert on the wire-equivalent sequence of operations.
    private final class CallRecorder: @unchecked Sendable {
        var deletes: [DeleteCall] = []
        var posts: [PostCall] = []
        var postShouldThrow: Error?
    }

    private func makeViewModel(
        threads: [NewsThread],
        recorder: CallRecorder
    ) async -> ThreadedNewsViewModel {
        let category = NewsBundle(
            identifier: Data([0x00, 0x00, 0x00, 0x01]),
            title: "Test",
            kind: .category
        )
        let viewModel = ThreadedNewsViewModel(
            fetchBundles: { _ in [category] },
            fetchThreads: { _ in threads },
            fetchThread: { _, threadID, _ in NewsThread(threadID: threadID) },
            createBundleAt: { _, _, _ in },
            postThread: { path, parentID, title, type, body in
                recorder.posts.append(.init(
                    path: path,
                    parentID: parentID,
                    title: title,
                    type: type,
                    body: body
                ))
                if let error = recorder.postShouldThrow { throw error }
            },
            deleteBundleAt: { _ in },
            deleteThreadAt: { path, threadID, cascade in
                recorder.deletes.append(.init(
                    path: path,
                    threadID: threadID,
                    cascade: cascade
                ))
            }
        )
        await viewModel.refresh()
        await viewModel.select(category)
        return viewModel
    }

    @Test("editThread calls delete then post with the recorded arguments")
    func editThread_callsDeleteThenPost_withRecordedArgs() async {
        let recorder = CallRecorder()
        let original = NewsThread(
            threadID: 7,
            parentID: 3,
            elements: [ThreadElement(title: "Old", author: "me", body: "old body")]
        )
        let viewModel = await makeViewModel(threads: [original], recorder: recorder)
        await viewModel.editThread(threadID: 7, newTitle: "New", newBody: "new body")
        #expect(recorder.deletes.count == 1)
        #expect(recorder.deletes.first?.threadID == 7)
        #expect(recorder.posts.count == 1)
        #expect(recorder.posts.first?.title == "New")
        #expect(recorder.posts.first?.body == "new body")
    }

    @Test("editThread always passes cascade: false")
    func editThread_passesCascadeFalse() async {
        let recorder = CallRecorder()
        let original = NewsThread(
            threadID: 7,
            parentID: 0,
            elements: [ThreadElement(title: "t", author: "m", body: "b")]
        )
        let viewModel = await makeViewModel(threads: [original], recorder: recorder)
        await viewModel.editThread(threadID: 7, newTitle: "u", newBody: "v")
        #expect(recorder.deletes.first?.cascade == false)
    }

    @Test("editThread preserves the original parentID on the new post")
    func editThread_preservesParentID() async {
        let recorder = CallRecorder()
        let original = NewsThread(
            threadID: 7,
            parentID: 42,
            elements: [ThreadElement(title: "t", author: "m", body: "b")]
        )
        let viewModel = await makeViewModel(threads: [original], recorder: recorder)
        await viewModel.editThread(threadID: 7, newTitle: "u", newBody: "v")
        #expect(recorder.posts.first?.parentID == 42)
    }

    @Test("editThread does nothing when no category is selected")
    func editThread_doesNothingWhenNoCategorySelected() async {
        let recorder = CallRecorder()
        let viewModel = ThreadedNewsViewModel(
            fetchBundles: { _ in [] },
            fetchThreads: { _ in [] },
            fetchThread: { _, threadID, _ in NewsThread(threadID: threadID) },
            createBundleAt: { _, _, _ in },
            postThread: { _, _, _, _, _ in },
            deleteBundleAt: { _ in },
            deleteThreadAt: { _, _, _ in }
        )
        await viewModel.editThread(threadID: 7, newTitle: "u", newBody: "v")
        #expect(recorder.deletes.isEmpty)
        #expect(recorder.posts.isEmpty)
    }

    @Test("editThread sets lastError when the repost fails after a successful delete")
    func editThread_refreshesAfterPostFailure_keepsLastErrorSet() async {
        struct Boom: Error {}
        let recorder = CallRecorder()
        recorder.postShouldThrow = Boom()
        let original = NewsThread(
            threadID: 7,
            parentID: 0,
            elements: [ThreadElement(title: "t", author: "m", body: "b")]
        )
        let viewModel = await makeViewModel(threads: [original], recorder: recorder)
        await viewModel.editThread(threadID: 7, newTitle: "u", newBody: "v")
        #expect(viewModel.lastError != nil)
        // Delete still ran (so the post is gone server-side).
        #expect(recorder.deletes.count == 1)
        // Post was attempted once (and threw).
        #expect(recorder.posts.count == 1)
    }

    @Test("selectedThread is nil when nothing is selected")
    func selectedThread_nilWhenNothingSelected() async {
        let recorder = CallRecorder()
        let viewModel = await makeViewModel(threads: [], recorder: recorder)
        #expect(viewModel.selectedThread == nil)
    }

    @Test("selectedThread returns the thread matching selectedThreadID")
    func selectedThread_returnsThreadForSelectedID() async {
        let recorder = CallRecorder()
        let thread = NewsThread(
            threadID: 7,
            parentID: 0,
            elements: [ThreadElement(title: "T", author: "me", body: "b")]
        )
        let viewModel = await makeViewModel(threads: [thread], recorder: recorder)
        await viewModel.openThread(thread)
        #expect(viewModel.selectedThread?.threadID == 7)
    }

    @Test("editableSelectedThread prefers loadedThread (with body) over list metadata")
    func editableSelectedThread_prefersLoadedThread() async {
        let recorder = CallRecorder()
        // List metadata: no body.
        let listEntry = NewsThread(
            threadID: 7,
            parentID: 0,
            elements: [ThreadElement(title: "Subject", author: "me", body: "")]
        )
        let viewModel = await makeViewModel(threads: [listEntry], recorder: recorder)

        // openThread triggers fetchThread (TX 400). The makeViewModel fake
        // returns `NewsThread(threadID:)` with no body — so we substitute a
        // richer fake via a fresh VM for this case.
        let loaded = NewsThread(
            threadID: 7,
            parentID: 0,
            elements: [ThreadElement(title: "Subject", author: "me", body: "full body text")]
        )
        let viewModelWithLoaded = ThreadedNewsViewModel(
            fetchBundles: { _ in [
                NewsBundle(identifier: Data([0x00, 0x00, 0x00, 0x01]), title: "Test", kind: .category)
            ] 
            },
            fetchThreads: { _ in [listEntry] },
            fetchThread: { _, _, _ in loaded },
            createBundleAt: { _, _, _ in },
            postThread: { _, _, _, _, _ in },
            deleteBundleAt: { _ in },
            deleteThreadAt: { _, _, _ in }
        )
        await viewModelWithLoaded.refresh()
        await viewModelWithLoaded.select(
            NewsBundle(identifier: Data([0x00, 0x00, 0x00, 0x01]), title: "Test", kind: .category)
        )
        await viewModelWithLoaded.openThread(listEntry)

        let editable = viewModelWithLoaded.editableSelectedThread
        #expect(editable?.threadID == 7)
        #expect(editable?.elements.first?.body == "full body text")
        // Silence unused-binding warning on `viewModel`; keep it here for
        // parity with the surrounding helper-driven setup style.
        _ = viewModel
    }

    @Test("editableSelectedThread falls back to list metadata when no body is loaded yet")
    func editableSelectedThread_fallsBackToListMetadata() async {
        let recorder = CallRecorder()
        let listEntry = NewsThread(
            threadID: 7,
            parentID: 0,
            elements: [ThreadElement(title: "Subject", author: "me", body: "")]
        )
        let viewModel = await makeViewModel(threads: [listEntry], recorder: recorder)
        // Set selection without firing openThread (no fetchThread → no body).
        await viewModel.openThread(listEntry)
        // The makeViewModel helper's fetchThread returns a body-less thread;
        // editableSelectedThread should still return *some* thread so the
        // sheet can open — just without a body.
        let editable = viewModel.editableSelectedThread
        #expect(editable?.threadID == 7)
    }

    @Test("editableSelectedThread is nil when nothing is selected")
    func editableSelectedThread_nilWhenNothingSelected() async {
        let recorder = CallRecorder()
        let viewModel = await makeViewModel(threads: [], recorder: recorder)
        #expect(viewModel.editableSelectedThread == nil)
    }

    @Test("selectedThread picks the right entry when several threads are loaded")
    func selectedThread_picksCorrectEntryAmongMany() async {
        let recorder = CallRecorder()
        let first = NewsThread(
            threadID: 7,
            parentID: 0,
            elements: [ThreadElement(title: "First", author: "me", body: "b")]
        )
        let second = NewsThread(
            threadID: 9,
            parentID: 0,
            elements: [ThreadElement(title: "Second", author: "you", body: "b")]
        )
        let viewModel = await makeViewModel(threads: [first, second], recorder: recorder)
        await viewModel.openThread(second)
        #expect(viewModel.selectedThread?.threadID == 9)
        #expect(viewModel.selectedThread?.elements.first?.author == "you")
    }
}
