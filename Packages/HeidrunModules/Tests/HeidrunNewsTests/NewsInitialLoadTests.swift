import Foundation
import Testing
@testable import HeidrunNews
import HeidrunCore

@Suite("NewsSurface.initial")
struct NewsSurfaceInitialTests {
    @Test("automatic opens threaded unless only the board has content",
          arguments: [
              (Bool?.some(false), Bool?.some(false), NewsSurface.threaded),
              (true, false, .board),
              (true, true, .threaded),
              (false, true, .threaded),
              (true, nil, .threaded),
              (nil, false, .threaded)
          ])
    func automatic(threadedIsEmpty: Bool?, boardIsEmpty: Bool?, expected: NewsSurface) {
        #expect(NewsSurface.initial(preference: .automatic, threadedIsEmpty: threadedIsEmpty, boardIsEmpty: boardIsEmpty) == expected)
    }

    @Test("a manual pick is honored even when empty")
    func manual() {
        #expect(NewsSurface.initial(preference: .board, threadedIsEmpty: false, boardIsEmpty: true) == .board)
        #expect(NewsSurface.initial(preference: .threaded, threadedIsEmpty: true, boardIsEmpty: false) == .threaded)
    }
}

@MainActor
@Suite("NewsInitialLoad")
struct NewsInitialLoadTests {
    nonisolated static let category = NewsBundle(identifier: Data([1]), title: "General", kind: .category)

    /// Fake server; `hangs` makes a fetch never return, like a lost reply.
    private final class FakeServer: @unchecked Sendable {
        var rootBundles: [NewsBundle] = []
        var feed = ""
        var hangsBoard = false
        var bundleFetches = 0
        var feedFetches = 0
    }

    private func makeViewModels(_ server: FakeServer) -> (PlainNewsViewModel, ThreadedNewsViewModel) {
        let plain = PlainNewsViewModel(
            events: AsyncStream { $0.finish() },
            fetchFeed: {
                server.feedFetches += 1
                if server.hangsBoard {
                    try await Task.sleep(for: .seconds(3600))
                }
                return server.feed
            },
            postNew: { _ in }
        )
        let threaded = ThreadedNewsViewModel(
            fetchBundles: { _ in
                server.bundleFetches += 1
                return server.rootBundles
            },
            fetchThreads: { _ in [] },
            fetchThread: { _, threadID, _ in NewsThread(threadID: threadID, elements: []) },
            createBundleAt: { _, _, _ in },
            postThread: { _, _, _, _, _ in },
            deleteBundleAt: { _ in },
            deleteThreadAt: { _, _, _ in }
        )
        return (plain, threaded)
    }

    private func runToEnd(_ threaded: ThreadedNewsViewModel) async {
        await threaded.download?.task?.value
    }

    @Test("auto-download fetches both and opens the board when threaded is empty")
    func bothFetchedBoardChosen() async {
        let server = FakeServer()
        server.feed = "Hello board"
        let (plain, threaded) = makeViewModels(server)
        NewsInitialLoad.start(plain: plain, threaded: threaded, preference: .automatic, downloadsBoth: true)
        await runToEnd(threaded)
        #expect(server.bundleFetches == 1)
        #expect(server.feedFetches == 1)
        #expect(threaded.surface == .board)
        #expect(threaded.download?.status == .completed)
        #expect(threaded.download?.fraction == 1)
    }

    @Test("threaded wins when both have content")
    func threadedDefault() async {
        let server = FakeServer()
        server.feed = "Hello board"
        server.rootBundles = [Self.category]
        let (plain, threaded) = makeViewModels(server)
        NewsInitialLoad.start(plain: plain, threaded: threaded, preference: .automatic, downloadsBoth: true)
        await runToEnd(threaded)
        #expect(threaded.surface == .threaded)
        #expect(threaded.bundles == [Self.category])
    }

    @Test("without auto-download, automatic only fetches the board when threaded is empty")
    func lazyFallback() async {
        let server = FakeServer()
        server.rootBundles = [Self.category]
        let (plain, threaded) = makeViewModels(server)
        NewsInitialLoad.start(plain: plain, threaded: threaded, preference: .automatic, downloadsBoth: false)
        await runToEnd(threaded)
        #expect(server.feedFetches == 0)
        #expect(threaded.download?.steps == [.threaded])

        let emptyServer = FakeServer()
        emptyServer.feed = "Board only"
        let (emptyPlain, emptyThreaded) = makeViewModels(emptyServer)
        NewsInitialLoad.start(plain: emptyPlain, threaded: emptyThreaded, preference: .automatic, downloadsBoth: false)
        await runToEnd(emptyThreaded)
        #expect(emptyServer.feedFetches == 1)
        #expect(emptyThreaded.surface == .board)
    }

    @Test("without auto-download, a board preference fetches only the board")
    func boardOnly() async {
        let server = FakeServer()
        server.rootBundles = [Self.category]
        let (plain, threaded) = makeViewModels(server)
        NewsInitialLoad.start(plain: plain, threaded: threaded, preference: .board, downloadsBoth: false)
        #expect(threaded.surface == .board)
        await runToEnd(threaded)
        #expect(server.bundleFetches == 0)
        #expect(server.feedFetches == 1)
        #expect(threaded.surface == .board)
    }

    @Test("runs once per connection")
    func oncePerConnection() async {
        let server = FakeServer()
        let (plain, threaded) = makeViewModels(server)
        NewsInitialLoad.start(plain: plain, threaded: threaded, preference: .automatic, downloadsBoth: true)
        await runToEnd(threaded)
        threaded.surface = .board
        NewsInitialLoad.start(plain: plain, threaded: threaded, preference: .automatic, downloadsBoth: true)
        await runToEnd(threaded)
        #expect(server.bundleFetches == 1)
        #expect(threaded.surface == .board)
    }

    @Test("cancel ends a hung fetch at once and keeps finished steps")
    func cancelHungFetch() async throws {
        let server = FakeServer()
        server.hangsBoard = true
        let (plain, threaded) = makeViewModels(server)
        NewsInitialLoad.start(plain: plain, threaded: threaded, preference: .automatic, downloadsBoth: true)
        let download = try #require(threaded.download)
        while download.stepStates[.threaded] != .done {
            await Task.yield()
        }
        #expect(download.fraction == 0.5)
        #expect(download.isFetching(.board))

        download.cancel()
        await runToEnd(threaded)
        guard case .failed = download.status else {
            Issue.record("expected failed, got \(download.status)")
            return
        }
        #expect(download.stepStates[.board] == .running)
        #expect(!plain.isLoading)
        #expect(threaded.surface == .threaded)

        threaded.clearFinishedDownload()
        #expect(threaded.download == nil)
    }

    @Test("caption lists each step's state")
    func caption() {
        let download = NewsDownload(steps: [.board, .threaded])
        download.begin(.board)
        download.finish(.board)
        download.begin(.threaded)
        #expect(download.caption == "Board ✓ · Threaded …")
        #expect(download.fraction == 0.5)
    }
}
