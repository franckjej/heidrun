import Foundation
import Testing
@testable import HeidrunFiles
import HeidrunCore

@Suite("FilesViewModel navigation history")
struct FilesViewModelHistoryTests {
    @Test("navigating records the previous folder and enables back")
    @MainActor
    func navigateRecordsHistory() async {
        let viewModel = makeViewModel()
        #expect(!viewModel.canGoBack)
        await viewModel.navigate(to: ["a"])
        await viewModel.navigate(to: ["a", "b"])
        #expect(viewModel.backStack == [[], ["a"]])
        #expect(viewModel.canGoBack)
        #expect(!viewModel.canGoForward)
    }

    @Test("navigating to the current folder records nothing")
    @MainActor
    func samePathIsNoOp() async {
        let viewModel = makeViewModel()
        await viewModel.navigate(to: ["a"])
        await viewModel.navigate(to: ["a"])
        #expect(viewModel.backStack == [[]])
    }

    @Test("back and forward walk the history and reload")
    @MainActor
    func backAndForward() async {
        let recorder = PathRecorder()
        let viewModel = makeViewModel(
            list: { path in
                await recorder.record(path)
                return []
            }
        )
        await viewModel.navigate(to: ["a"])
        await viewModel.navigateInto(RemoteFile(name: "b", type: .folder, itemCount: 0))
        await viewModel.goBack()
        #expect(viewModel.currentPath == ["a"])
        #expect(viewModel.forwardStack == [["a", "b"]])
        await viewModel.goBack()
        #expect(viewModel.currentPath.isRoot)
        #expect(!viewModel.canGoBack)
        await viewModel.goForward()
        #expect(viewModel.currentPath == ["a"])
        await viewModel.goForward()
        #expect(viewModel.currentPath == ["a", "b"])
        #expect(!viewModel.canGoForward)
        let visited = await recorder.paths
        #expect(visited.last == ["a", "b"])
    }

    @Test("going back on an empty history does nothing")
    @MainActor
    func backOnEmptyHistory() async {
        let viewModel = makeViewModel()
        await viewModel.goBack()
        await viewModel.goForward()
        #expect(viewModel.currentPath.isRoot)
    }

    @Test("a new navigation clears the forward history")
    @MainActor
    func newNavigationClearsForward() async {
        let viewModel = makeViewModel()
        await viewModel.navigate(to: ["a"])
        await viewModel.goBack()
        #expect(viewModel.canGoForward)
        await viewModel.navigate(to: ["c"])
        #expect(!viewModel.canGoForward)
        #expect(viewModel.backStack == [[]])
    }

    @Test("navigateUp is recorded")
    @MainActor
    func navigateUpRecorded() async {
        let viewModel = makeViewModel()
        await viewModel.navigate(to: ["a", "b"])
        await viewModel.navigateUp()
        await viewModel.goBack()
        #expect(viewModel.currentPath == ["a", "b"])
    }

    @Test("a refused drop box falls back without leaving its parent on the back stack")
    @MainActor
    func dropBoxFallbackPrunesHistory() async {
        let viewModel = makeViewModel(
            list: { path in
                if path.containsDropBox { throw HotlineError.serverError(id: 1, message: "nope") }
                return []
            },
            present: { _ in }
        )
        viewModel.updatePrivileges([.downloadFiles])
        await viewModel.navigate(to: ["Public"])
        await viewModel.navigate(to: ["Public", "Drop Box"])
        #expect(viewModel.currentPath == ["Public"])
        #expect(viewModel.backStack == [[]])
    }
}
