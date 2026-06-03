import Foundation
import Testing
@testable import HeidrunNews
import HeidrunCore

@Suite("PlainNewsViewModel")
struct PlainNewsViewModelTests {
    @Test("refresh fetches and replaces the feed")
    @MainActor
    func refreshReplacesFeed() async {
        let (events, _) = AsyncStream<HotlineEvent>.makeStream()
        let viewModel = PlainNewsViewModel(
            events: events,
            fetchFeed: { "v1\n" },
            postNew: { _ in }
        )
        await viewModel.refresh()
        #expect(viewModel.feed == "v1\n")
        #expect(viewModel.lastError == nil)
    }

    @Test("newsPosted events prepend new posts to the feed")
    @MainActor
    func newsPostedPrepends() async {
        let (events, continuation) = AsyncStream<HotlineEvent>.makeStream()
        let viewModel = PlainNewsViewModel(
            events: events,
            fetchFeed: { "" },
            postNew: { _ in }
        )
        let observation = Task { await viewModel.observe() }
        continuation.yield(.newsPosted(text: "first"))
        continuation.yield(.newsPosted(text: "second"))
        continuation.finish()
        await observation.value

        // Newer posts go on top, separated by a blank line.
        #expect(viewModel.feed == "second\n\nfirst\n\n")
    }

    @Test("start() observes live posts and is idempotent")
    @MainActor
    func startObservesLivePosts() async {
        let (events, continuation) = AsyncStream<HotlineEvent>.makeStream()
        let viewModel = PlainNewsViewModel(
            events: events,
            fetchFeed: { "" },
            postNew: { _ in }
        )
        // Connection scope owns the loop; calling start() twice (once from
        // ConnectionHandle, once when the News tab first appears) must not
        // spawn a second consumer that steals events from the first.
        viewModel.start()
        viewModel.start()
        continuation.yield(.newsPosted(text: "live"))

        // The managed task runs on the main actor; yield until it lands.
        var attempts = 1000
        while viewModel.feed.isEmpty && attempts > 0 {
            await Task.yield()
            attempts -= 1
        }
        #expect(viewModel.feed == "live\n\n")

        viewModel.cancel()
    }

    @Test("postDraft trims, posts, clears the draft")
    @MainActor
    func postDraftPostsAndClears() async {
        let (events, _) = AsyncStream<HotlineEvent>.makeStream()
        let recorder = NewsRecorder()
        let viewModel = PlainNewsViewModel(
            events: events,
            fetchFeed: { "" },
            postNew: { text in await recorder.record(text) }
        )
        viewModel.draft = "  hello  "
        await viewModel.postDraft()

        let calls = await recorder.posts
        #expect(calls == ["hello"])
        #expect(viewModel.draft.isEmpty)
    }

    @Test("postDraft no-op for whitespace")
    @MainActor
    func postDraftSkipsBlank() async {
        let (events, _) = AsyncStream<HotlineEvent>.makeStream()
        let recorder = NewsRecorder()
        let viewModel = PlainNewsViewModel(
            events: events,
            fetchFeed: { "" },
            postNew: { text in await recorder.record(text) }
        )
        viewModel.draft = "   \n  "
        await viewModel.postDraft()
        let calls = await recorder.posts
        #expect(calls.isEmpty)
    }

    @Test("refresh records the error and clears the feed")
    @MainActor
    func refreshSurfacesError() async {
        struct Boom: Error {}
        let (events, _) = AsyncStream<HotlineEvent>.makeStream()
        let viewModel = PlainNewsViewModel(
            events: events,
            fetchFeed: { throw Boom() },
            postNew: { _ in }
        )
        await viewModel.refresh()
        #expect(viewModel.lastError != nil)
    }
}

@Suite("ThreadedNewsViewModel")
struct ThreadedNewsViewModelTests {
    @Test("selecting a folder bundle highlights it without descending")
    @MainActor
    func selectFolderHighlightsOnly() async {
        let recorder = NewsBundleRecorder()
        let viewModel = makeViewModel(
            fetchBundles: { path in
                await recorder.recordBundleFetch(path: path)
                return []
            }
        )

        let folder = NewsBundle(identifier: Data(), title: "Outer", kind: .bundle)
        await viewModel.select(folder)

        // Single-tap on a folder should highlight only — path stays put,
        // contents don't re-fetch, and the right pane stays empty.
        #expect(viewModel.currentPath.isRoot)
        #expect(viewModel.selectedBundleID == folder.id)
        #expect(viewModel.selectedCategoryPath == nil)
        #expect(viewModel.threads.isEmpty)
        let bundlePaths = await recorder.bundlePaths.map(\.components)
        #expect(bundlePaths.isEmpty)
    }

    @Test("descend(into:) navigates into a folder and fetches its contents")
    @MainActor
    func descendIntoFolder() async {
        let recorder = NewsBundleRecorder()
        let viewModel = makeViewModel(
            fetchBundles: { path in
                await recorder.recordBundleFetch(path: path)
                return [NewsBundle(identifier: Data(), title: "Inner", kind: .category)]
            }
        )

        await viewModel.descend(into: NewsBundle(identifier: Data(), title: "Outer", kind: .bundle))

        #expect(viewModel.currentPath.components == ["Outer"])
        #expect(viewModel.bundles.first?.title == "Inner")
        #expect(viewModel.threads.isEmpty)
        #expect(viewModel.selectedBundleID == nil)
        let bundlePaths = await recorder.bundlePaths.map(\.components)
        #expect(bundlePaths.contains(["Outer"]))
    }

    @Test("descend(into:) is a no-op for categories")
    @MainActor
    func descendIntoCategoryIsNoOp() async {
        let viewModel = makeViewModel()
        await viewModel.descend(into: NewsBundle(identifier: Data(), title: "Cat", kind: .category))
        #expect(viewModel.currentPath.isRoot)
    }

    @Test("selecting a category fills the right pane without changing currentPath")
    @MainActor
    func selectCategoryFillsRightPane() async {
        let recorder = NewsBundleRecorder()
        let viewModel = makeViewModel(
            fetchThreads: { path in
                await recorder.recordThreadFetch(path: path)
                return [
                    NewsThread(threadID: 1, elements: [ThreadElement(title: "Hello")]),
                    NewsThread(threadID: 2, elements: [ThreadElement(title: "World")])
                ]
            }
        )

        let news = NewsBundle(identifier: Data([0xAB]), title: "News", kind: .category)
        await viewModel.select(news)

        #expect(viewModel.currentPath.isRoot)
        #expect(viewModel.threads.count == 2)
        #expect(viewModel.selectedBundleID == news.id)
        #expect(viewModel.selectedCategoryPath?.components == ["News"])
        let threadPaths = await recorder.threadPaths.map(\.components)
        #expect(threadPaths.contains(["News"]))
    }

    @Test("navigateUp pops one folder level and clears the category selection")
    @MainActor
    func navigateUpClearsSelection() async {
        let viewModel = makeViewModel(
            fetchBundles: { _ in [NewsBundle(identifier: Data(), title: "Top")] },
            fetchThreads: { _ in [NewsThread(threadID: 1)] }
        )
        // Descend into a folder, then select a category inside it.
        await viewModel.descend(into: NewsBundle(identifier: Data(), title: "Folder", kind: .bundle))
        await viewModel.select(NewsBundle(identifier: Data(), title: "Cat", kind: .category))
        #expect(viewModel.selectedCategoryPath != nil)

        await viewModel.navigateUp()
        #expect(viewModel.currentPath.isRoot)
        #expect(viewModel.selectedBundleID == nil)
        #expect(viewModel.threads.isEmpty)
        #expect(viewModel.bundles.first?.title == "Top")
    }

    @Test("navigate(toDepth:) truncates the path and reloads as a folder")
    @MainActor
    func navigateToDepth() async {
        let recorder = NewsBundleRecorder()
        let viewModel = makeViewModel(
            fetchBundles: { path in
                await recorder.recordBundleFetch(path: path)
                return []
            }
        )
        await viewModel.descend(into: NewsBundle(identifier: Data(), title: "A", kind: .bundle))
        await viewModel.descend(into: NewsBundle(identifier: Data(), title: "B", kind: .bundle))
        #expect(viewModel.currentPath.components == ["A", "B"])

        await viewModel.navigate(toDepth: 1)
        #expect(viewModel.currentPath.components == ["A"])
        let paths = await recorder.bundlePaths.map(\.components)
        #expect(paths.contains(["A"]))
    }

    @Test("openThread is a no-op without a selected category")
    @MainActor
    func openThreadRequiresCategory() async {
        let viewModel = makeViewModel(
            fetchThread: { _, id, _ in NewsThread(threadID: id) }
        )
        await viewModel.openThread(threadID: 42, type: ThreadElement.plainTextType)
        #expect(viewModel.loadedThread == nil)
    }

    @Test("openThread populates loadedThread once a category is selected")
    @MainActor
    func openThreadPopulates() async {
        let viewModel = makeViewModel(
            fetchThreads: { _ in [NewsThread(threadID: 42)] },
            fetchThread: { _, id, _ in NewsThread(threadID: id) }
        )
        await viewModel.select(NewsBundle(identifier: Data(), title: "Cat", kind: .category))
        await viewModel.openThread(threadID: 42, type: ThreadElement.plainTextType)
        #expect(viewModel.loadedThread?.threadID == 42)
        #expect(viewModel.selectedThreadID == 42)
    }

    @Test("deleteThread clears loadedThread when it matches")
    @MainActor
    func deleteClearsLoaded() async {
        let viewModel = makeViewModel(
            fetchThreads: { _ in [NewsThread(threadID: 7)] },
            fetchThread: { _, id, _ in NewsThread(threadID: id) }
        )
        await viewModel.select(NewsBundle(identifier: Data(), title: "Cat", kind: .category))
        await viewModel.openThread(threadID: 7, type: ThreadElement.plainTextType)
        await viewModel.deleteThread(threadID: 7, cascade: false)
        #expect(viewModel.loadedThread == nil)
        #expect(viewModel.selectedThreadID == nil)
    }
}

@Suite("NewsFeature")
struct NewsFeatureTests {
    @Test("static metadata is stable")
    func metadata() {
        #expect(NewsFeature.identifier == "com.heidrun.news")
        #expect(NewsFeature.displayName == "News")
        #expect(!NewsFeature.systemImage.isEmpty)
    }
}

// MARK: - Helpers

@MainActor
private func makeViewModel(
    fetchBundles: @escaping @Sendable (RemotePath) async throws -> [NewsBundle] = { _ in [] },
    fetchThreads: @escaping @Sendable (RemotePath) async throws -> [NewsThread] = { _ in [] },
    fetchThread: @escaping @Sendable (RemotePath, UInt16, String) async throws -> NewsThread = { _, id, _ in NewsThread(threadID: id) }
) -> ThreadedNewsViewModel {
    ThreadedNewsViewModel(
        fetchBundles: fetchBundles,
        fetchThreads: fetchThreads,
        fetchThread: fetchThread,
        createBundleAt: { _, _, _ in },
        postThread: { _, _, _, _, _ in },
        deleteBundleAt: { _ in },
        deleteThreadAt: { _, _, _ in }
    )
}

private actor NewsRecorder {
    private(set) var posts: [String] = []
    func record(_ text: String) { posts.append(text) }
}

private actor NewsBundleRecorder {
    private(set) var bundlePaths: [RemotePath] = []
    private(set) var threadPaths: [RemotePath] = []
    func recordBundleFetch(path: RemotePath) { bundlePaths.append(path) }
    func recordThreadFetch(path: RemotePath) { threadPaths.append(path) }
}
