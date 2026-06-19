import Foundation
import Testing
@testable import HeidrunNews
import HeidrunCore

@MainActor
@Suite("ThreadedNewsViewModel post-count badge")
struct ThreadedNewsViewModelCountTests {
    /// Mutable post count shared by the fetchBundles/fetchThreads fakes so a
    /// delete can drop the category's reported `size` (the left-pane badge)
    /// the way a real server recomputes it on the next TX 370.
    private final class Store: @unchecked Sendable {
        var postCount: UInt16 = 1
    }

    private static let category = NewsBundle(
        identifier: Data([0x00, 0x00, 0x00, 0x01]),
        title: "news",
        kind: .category,
        size: 1
    )

    private func makeViewModel(_ store: Store) async -> ThreadedNewsViewModel {
        let viewModel = ThreadedNewsViewModel(
            fetchBundles: { _ in
                let bundle = NewsBundle(
                    identifier: Data([0x00, 0x00, 0x00, 0x01]),
                    title: "news",
                    kind: .category,
                    size: store.postCount
                )
                return [bundle]
            },
            fetchThreads: { _ in
                store.postCount == 0 ? [] : [NewsThread(threadID: 1)]
            },
            fetchThread: { _, threadID, _ in NewsThread(threadID: threadID) },
            createBundleAt: { _, _, _ in },
            postThread: { _, _, _, _, _ in store.postCount += 1 },
            deleteBundleAt: { _ in },
            deleteThreadAt: { _, _, _ in store.postCount = 0 }
        )
        await viewModel.refresh()
        await viewModel.select(Self.category)
        return viewModel
    }

    @Test("deleting a thread drops the category badge to the new server count")
    func deleteThreadUpdatesBadge() async {
        let store = Store()
        let viewModel = await makeViewModel(store)
        #expect(viewModel.bundles.first?.size == 1)

        await viewModel.deleteThread(threadID: 1, cascade: false)

        #expect(viewModel.bundles.first?.size == 0)
    }

    @Test("refresh updates the badge while a category is selected")
    func refreshUpdatesBadgeWithCategorySelected() async {
        let store = Store()
        let viewModel = await makeViewModel(store)
        store.postCount = 0   // server-side change between fetches

        await viewModel.refresh()

        #expect(viewModel.bundles.first?.size == 0)
    }

    @Test("posting a thread bumps the category badge")
    func postUpdatesBadge() async {
        let store = Store()
        let viewModel = await makeViewModel(store)

        await viewModel.post(title: "Hello", body: "world")

        #expect(viewModel.bundles.first?.size == 2)
    }
}
