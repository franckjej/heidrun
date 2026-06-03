import Foundation
import Testing
@testable import HeidrunNews
import HeidrunCore

@MainActor
@Suite("NewsThreadActions.canEdit")
struct NewsThreadActionsTests {
    /// Fresh stub VM — `canEdit` doesn't touch the VM, so empty
    /// closures are fine.
    private func stubViewModel() -> ThreadedNewsViewModel {
        ThreadedNewsViewModel(
            fetchBundles: { _ in [] },
            fetchThreads: { _ in [] },
            fetchThread: { _, threadID, _ in NewsThread(threadID: threadID) },
            createBundleAt: { _, _, _ in },
            postThread: { _, _, _, _, _ in },
            deleteBundleAt: { _ in },
            deleteThreadAt: { _, _, _ in }
        )
    }

    private func thread(author: String) -> NewsThread {
        NewsThread(
            threadID: 1,
            elements: [ThreadElement(title: "t", author: author, body: "b")]
        )
    }

    @Test("canEdit returns true when author equals own nickname")
    func canEdit_ownPost_true() {
        let actions = NewsThreadActions(
            viewModel: stubViewModel(),
            ownNickname: "Erika",
            onEdit: { _ in },
            onConfirmDelete: { _ in },
            onReply: { _ in }
        )
        #expect(actions.canEdit(thread(author: "Erika")) == true)
    }

    @Test("canEdit returns false when author differs from own nickname")
    func canEdit_othersPost_false() {
        let actions = NewsThreadActions(
            viewModel: stubViewModel(),
            ownNickname: "Erika",
            onEdit: { _ in },
            onConfirmDelete: { _ in },
            onReply: { _ in }
        )
        #expect(actions.canEdit(thread(author: "Klaus")) == false)
    }

    @Test("canEdit returns false when the author field is empty")
    func canEdit_emptyAuthor_false() {
        let actions = NewsThreadActions(
            viewModel: stubViewModel(),
            ownNickname: "Erika",
            onEdit: { _ in },
            onConfirmDelete: { _ in },
            onReply: { _ in }
        )
        #expect(actions.canEdit(thread(author: "")) == false)
    }

    @Test("canEdit returns false when own nickname is empty (pre-login)")
    func canEdit_emptyOwnNickname_false() {
        let actions = NewsThreadActions(
            viewModel: stubViewModel(),
            ownNickname: "",
            onEdit: { _ in },
            onConfirmDelete: { _ in },
            onReply: { _ in }
        )
        #expect(actions.canEdit(thread(author: "Erika")) == false)
    }

    @Test("replyTitle prefixes a plain parent title with Re:")
    func replyTitle_plainParent() {
        #expect(NewsThreadActions.replyTitle(forParent: "Welcome") == "Re: Welcome")
    }

    @Test("replyTitle keeps chains one Re: deep, not Re: Re: Re:")
    func replyTitle_collapsesChain() {
        #expect(
            NewsThreadActions.replyTitle(forParent: "Re: Re: Welcome") == "Re: Welcome"
        )
    }

    @Test("replyTitle is case-insensitive on the existing prefix")
    func replyTitle_caseInsensitive() {
        // Some clients/users type "re: " lowercase; still one Re: deep.
        #expect(NewsThreadActions.replyTitle(forParent: "re: hi") == "Re: hi")
        #expect(NewsThreadActions.replyTitle(forParent: "RE: HI") == "Re: HI")
    }

    @Test("replyTitle handles an empty parent title")
    func replyTitle_emptyParent() {
        #expect(NewsThreadActions.replyTitle(forParent: "") == "Re: ")
    }
}
