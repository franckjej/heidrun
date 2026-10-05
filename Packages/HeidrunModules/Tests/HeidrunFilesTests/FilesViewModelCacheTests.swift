import Foundation
import Testing
@testable import HeidrunFiles
import HeidrunCore

/// Fake server whose listings the test can change, and which can hold
/// the next listing call until released.
actor FakeListingServer {
    private var listings: [RemotePath: [RemoteFile]] = [:]
    private var armed = false
    private var held: CheckedContinuation<Void, Never>?
    private var arrival: CheckedContinuation<Void, Never>?

    func set(_ names: [String], at path: RemotePath) {
        listings[path] = names.map { RemoteFile(name: $0) }
    }

    func list(_ path: RemotePath) async throws -> [RemoteFile] {
        if armed {
            armed = false
            await withCheckedContinuation { continuation in
                held = continuation
                arrival?.resume()
                arrival = nil
            }
        }
        guard let listing = listings[path] else {
            throw HotlineError.serverError(id: 1, message: "gone")
        }
        return listing
    }

    func remove(at path: RemotePath) { listings[path] = nil }

    /// Hold the next `list` call.
    func holdNext() { armed = true }

    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() {
        held?.resume()
        held = nil
    }
}

@Suite("FilesViewModel listing cache")
struct FilesViewModelCacheTests {
    @MainActor
    private func makeCachedViewModel(_ server: FakeListingServer) -> FilesViewModel {
        makeViewModel(list: { path in try await server.list(path) })
    }

    @Test("going back shows the cached listing before the server answers")
    @MainActor
    func backShowsCachedListing() async {
        let server = FakeListingServer()
        await server.set(["a-old"], at: ["a"])
        await server.set(["b-file"], at: ["b"])
        let viewModel = makeCachedViewModel(server)
        await viewModel.navigate(to: ["a"])
        await viewModel.navigate(to: ["b"])
        await server.set(["a-new"], at: ["a"])

        await server.holdNext()
        let navigation = Task { await viewModel.goBack() }
        await server.waitUntilHeld()
        #expect(viewModel.currentPath == ["a"])
        #expect(viewModel.files.map(\.name) == ["a-old"])

        await server.release()
        await navigation.value
        #expect(viewModel.files.map(\.name) == ["a-new"])
    }

    @Test("an uncached folder shows no rows, not the previous folder's, until the server answers")
    @MainActor
    func cacheMissClearsOldRows() async {
        let server = FakeListingServer()
        await server.set(["a-file"], at: ["a"])
        await server.set(["b-file"], at: ["b"])
        let viewModel = makeCachedViewModel(server)
        await viewModel.navigate(to: ["a"])

        await server.holdNext()
        let navigation = Task { await viewModel.navigate(to: ["b"]) }
        await server.waitUntilHeld()
        #expect(viewModel.currentPath == ["b"])
        #expect(viewModel.files.isEmpty)

        await server.release()
        await navigation.value
        #expect(viewModel.files.map(\.name) == ["b-file"])
    }

    @Test("a failed listing after a cache hit clears the rows and the cache entry")
    @MainActor
    func failedRefreshAfterCacheHit() async {
        let server = FakeListingServer()
        await server.set(["a-file"], at: ["a"])
        await server.set([], at: ["b"])
        var presented = 0
        let viewModel = makeViewModel(
            list: { path in try await server.list(path) },
            present: { _ in presented += 1 }
        )
        await viewModel.navigate(to: ["a"])
        await viewModel.navigate(to: ["b"])
        await server.remove(at: ["a"])

        await viewModel.goBack()
        #expect(viewModel.files.isEmpty)
        #expect(presented == 1)
        #expect(viewModel.listingCache[["a"]] == nil)
    }

    @Test("a refresh after a mutation updates the cache")
    @MainActor
    func mutationRefreshUpdatesCache() async {
        let server = FakeListingServer()
        await server.set(["one"], at: ["a"])
        let viewModel = makeCachedViewModel(server)
        await viewModel.navigate(to: ["a"])
        await server.set(["one", "two"], at: ["a"])
        await viewModel.createFolder(named: "two")
        #expect(viewModel.listingCache[["a"]]?.map(\.name) == ["one", "two"])
    }

    @Test("a slow listing for a folder already left doesn't replace the newer rows")
    @MainActor
    func staleListingIgnored() async {
        let server = FakeListingServer()
        await server.set(["a-file"], at: ["a"])
        await server.set(["b-file"], at: ["b"])
        let viewModel = makeCachedViewModel(server)

        await server.holdNext()
        let slow = Task { await viewModel.navigate(to: ["a"]) }
        await server.waitUntilHeld()
        await viewModel.navigate(to: ["b"])
        await server.release()
        await slow.value

        #expect(viewModel.currentPath == ["b"])
        #expect(viewModel.files.map(\.name) == ["b-file"])
        #expect(viewModel.listingCache[["a"]]?.map(\.name) == ["a-file"])
    }
}
