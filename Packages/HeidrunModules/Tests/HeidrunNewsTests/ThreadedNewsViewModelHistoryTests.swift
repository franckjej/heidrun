import Foundation
import Testing
@testable import HeidrunNews
import HeidrunCore

@MainActor
@Suite("ThreadedNewsViewModel history")
struct ThreadedNewsViewModelHistoryTests {
    nonisolated static let folder = NewsBundle(identifier: Data([1]), title: "Folder", kind: .bundle)
    nonisolated static let alpha = NewsBundle(identifier: Data([2]), title: "Alpha", kind: .category)
    nonisolated static let beta = NewsBundle(identifier: Data([3]), title: "Beta", kind: .category)
    nonisolated static let first = NewsThread(threadID: 1, elements: [ThreadElement(title: "First")])
    nonisolated static let second = NewsThread(threadID: 2, parentID: 1, elements: [ThreadElement(title: "Second")])

    /// Fake server tree; `threadsSeen` records the VM's thread IDs at each
    /// bundle fetch, to prove cached rows show before the server answers.
    private final class FakeServer: @unchecked Sendable {
        var bundles: [RemotePath: [NewsBundle]] = [
            []: [folder, alpha, beta],
            ["Folder"]: []
        ]
        var threads: [RemotePath: [NewsThread]] = [
            ["Alpha"]: [first, second],
            ["Beta"]: []
        ]
        var failThreads = false
        var threadsSeen: [[UInt16]] = []
        weak var viewModel: ThreadedNewsViewModel?
    }

    private struct FetchFailed: Error {}

    private func makeViewModel(_ server: FakeServer) async -> ThreadedNewsViewModel {
        let viewModel = ThreadedNewsViewModel(
            fetchBundles: { path in
                let seen = await MainActor.run { server.viewModel?.threads.map(\.threadID) ?? [] }
                server.threadsSeen.append(seen)
                return server.bundles[path] ?? []
            },
            fetchThreads: { path in
                if server.failThreads { throw FetchFailed() }
                return server.threads[path] ?? []
            },
            fetchThread: { _, threadID, _ in
                NewsThread(threadID: threadID, elements: [ThreadElement(body: "body \(threadID)")])
            },
            createBundleAt: { _, _, _ in },
            postThread: { _, _, _, _, _ in },
            deleteBundleAt: { _ in },
            deleteThreadAt: { _, _, _ in }
        )
        server.viewModel = viewModel
        await viewModel.refresh()
        return viewModel
    }

    private var root: NewsLocation { NewsLocation(path: []) }
    private var atAlpha: NewsLocation { NewsLocation(path: [], bundleID: Self.alpha.id) }

    @Test("picking a category and clicking a thread each add a step")
    func clicksAddSteps() async {
        let viewModel = await makeViewModel(FakeServer())
        #expect(!viewModel.canGoBack)
        await viewModel.select(Self.alpha)
        await viewModel.openThread(Self.first)
        #expect(viewModel.backStack == [root, atAlpha])
        #expect(viewModel.canGoBack)
        #expect(!viewModel.canGoForward)
    }

    @Test("keyboard selection replaces the current step")
    func keyboardReplaces() async {
        let viewModel = await makeViewModel(FakeServer())
        await viewModel.select(Self.alpha)
        await viewModel.openThread(Self.first)
        await viewModel.openThread(Self.second, replacesHistory: true)
        #expect(viewModel.backStack == [root, atAlpha])
        #expect(viewModel.selectedThreadID == 2)
    }

    @Test("staying put records nothing")
    func samePlaceIsNoOp() async {
        let viewModel = await makeViewModel(FakeServer())
        await viewModel.select(Self.alpha)
        await viewModel.select(Self.alpha)
        #expect(viewModel.backStack == [root])
    }

    @Test("back restores folder, category and thread; forward returns")
    func backAndForward() async {
        let viewModel = await makeViewModel(FakeServer())
        await viewModel.select(Self.alpha)
        await viewModel.openThread(Self.second)
        await viewModel.descend(into: Self.folder)
        #expect(viewModel.currentPath == ["Folder"])

        await viewModel.goBack()
        #expect(viewModel.currentPath.isRoot)
        #expect(viewModel.selectedBundleID == Self.alpha.id)
        #expect(viewModel.threads.map(\.threadID) == [1, 2])
        #expect(viewModel.selectedThreadID == 2)
        #expect(viewModel.loadedThread?.elements.first?.body == "body 2")
        #expect(viewModel.forwardStack == [NewsLocation(path: ["Folder"])])

        await viewModel.goForward()
        #expect(viewModel.currentPath == ["Folder"])
        #expect(viewModel.selectedBundleID == nil)
        #expect(!viewModel.canGoForward)
    }

    @Test("a new step clears forward")
    func newStepClearsForward() async {
        let viewModel = await makeViewModel(FakeServer())
        await viewModel.select(Self.alpha)
        await viewModel.goBack()
        #expect(viewModel.canGoForward)
        await viewModel.select(Self.beta)
        #expect(!viewModel.canGoForward)
    }

    @Test("back shows the cached threads while the server refreshes")
    func cachedRowsFirst() async {
        let server = FakeServer()
        let viewModel = await makeViewModel(server)
        await viewModel.select(Self.alpha)
        await viewModel.descend(into: Self.folder)
        server.threadsSeen.removeAll()
        await viewModel.goBack()
        #expect(server.threadsSeen.first == [1, 2])
    }

    @Test("a thread deleted since lands on its category")
    func deletedThreadFallsBack() async {
        let server = FakeServer()
        let viewModel = await makeViewModel(server)
        await viewModel.select(Self.alpha)
        await viewModel.openThread(Self.second)
        await viewModel.select(Self.beta)
        server.threads[["Alpha"]] = [Self.first]
        await viewModel.goBack()
        #expect(viewModel.selectedBundleID == Self.alpha.id)
        #expect(viewModel.selectedThreadID == nil)
        #expect(viewModel.loadedThread == nil)
    }

    @Test("a category deleted since lands on its folder")
    func deletedCategoryFallsBack() async {
        let server = FakeServer()
        let viewModel = await makeViewModel(server)
        await viewModel.select(Self.alpha)
        await viewModel.descend(into: Self.folder)
        server.bundles[[]] = [Self.folder]
        await viewModel.goBack()
        #expect(viewModel.currentPath.isRoot)
        #expect(viewModel.selectedBundleID == nil)
        #expect(viewModel.threads.isEmpty)
    }

    @Test("a failed fetch drops the cached threads")
    func failedFetchDropsCache() async {
        let server = FakeServer()
        let viewModel = await makeViewModel(server)
        await viewModel.select(Self.alpha)
        await viewModel.descend(into: Self.folder)
        server.failThreads = true
        await viewModel.goBack()
        #expect(viewModel.threadsCache[["Alpha"]] == nil)
        #expect(viewModel.threads.isEmpty)
    }

    @Test("the view hears about each location left, not replaced ones")
    func willLeaveCallback() async {
        let viewModel = await makeViewModel(FakeServer())
        var left: [NewsLocation] = []
        viewModel.onWillLeaveLocation = { left.append($0) }
        await viewModel.select(Self.alpha)
        await viewModel.openThread(Self.first)
        await viewModel.openThread(Self.second, replacesHistory: true)
        await viewModel.goBack()
        #expect(left == [
            root,
            atAlpha,
            NewsLocation(path: [], bundleID: Self.alpha.id, threadID: 2)
        ])
    }
}
