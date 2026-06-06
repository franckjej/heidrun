import Foundation
import Testing
@testable import HeidrunNews
import HeidrunCore

@MainActor
@Suite("ThreadedNewsViewModel.copyText")
struct ThreadedNewsViewModelCopyTests {
    private static let fixedDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 24
        components.hour = 14
        components.minute = 32
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    /// Build a VM with a single category at root that already has the
    /// given threads loaded into the right pane.
    private func makeViewModelWithThreads(_ threads: [NewsThread]) async -> ThreadedNewsViewModel {
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
            postThread: { _, _, _, _, _ in },
            deleteBundleAt: { _ in },
            deleteThreadAt: { _, _, _ in }
        )
        await viewModel.refresh()
        await viewModel.select(category)
        return viewModel
    }

    @Test("copyText(.post) returns formatPost output")
    func copyText_post_returnsFormatted() async {
        let thread = NewsThread(
            threadID: 5,
            postDate: Self.fixedDate,
            elements: [ThreadElement(title: "T", author: "A", body: "B")]
        )
        let viewModel = await makeViewModelWithThreads([thread])
        let copied = viewModel.copyText(threadID: 5, scope: .post)
        #expect(copied == NewsClipboardFormatter.formatPost(thread))
    }

    @Test("copyText(.thread) returns the formatter's tree output")
    func copyText_thread_returnsTreeOutput() async {
        let parent = NewsThread(
            threadID: 5,
            postDate: Self.fixedDate,
            elements: [ThreadElement(title: "P", author: "A", body: "p")]
        )
        let reply = NewsThread(
            threadID: 6,
            parentID: 5,
            postDate: Self.fixedDate.addingTimeInterval(60),
            elements: [ThreadElement(title: "R", author: "B", body: "r")]
        )
        let viewModel = await makeViewModelWithThreads([parent, reply])
        let copied = viewModel.copyText(threadID: 5, scope: .thread)
        let expected = NewsClipboardFormatter.formatThread(parent, descendantsFrom: [parent, reply])
        #expect(copied == expected)
    }

    @Test("copyText with an unknown threadID returns nil")
    func copyText_unknownThreadID_returnsNil() async {
        let viewModel = await makeViewModelWithThreads([])
        #expect(viewModel.copyText(threadID: 999, scope: .post) == nil)
        #expect(viewModel.copyText(threadID: 999, scope: .thread) == nil)
    }

    private struct StubFetchError: Error {}

    @Test("selectedBundle is nil when nothing is selected")
    func selectedBundle_nilWhenNothingSelected() async {
        let folder = NewsBundle(
            identifier: Data([0x00, 0x00, 0x00, 0x01]),
            title: "Folder",
            kind: .bundle
        )
        let viewModel = ThreadedNewsViewModel(
            fetchBundles: { _ in [folder] },
            fetchThreads: { _ in [] },
            fetchThread: { _, threadID, _ in NewsThread(threadID: threadID) },
            createBundleAt: { _, _, _ in },
            postThread: { _, _, _, _, _ in },
            deleteBundleAt: { _ in },
            deleteThreadAt: { _, _, _ in }
        )
        await viewModel.refresh()
        #expect(viewModel.selectedBundle == nil)
    }

    @Test("selectedBundle returns the highlighted bundle")
    func selectedBundle_returnsHighlighted() async {
        let folder = NewsBundle(
            identifier: Data([0x00, 0x00, 0x00, 0x01]),
            title: "Folder",
            kind: .bundle
        )
        let viewModel = ThreadedNewsViewModel(
            fetchBundles: { _ in [folder] },
            fetchThreads: { _ in [] },
            fetchThread: { _, threadID, _ in NewsThread(threadID: threadID) },
            createBundleAt: { _, _, _ in },
            postThread: { _, _, _, _, _ in },
            deleteBundleAt: { _ in },
            deleteThreadAt: { _, _, _ in }
        )
        await viewModel.refresh()
        await viewModel.select(folder)
        #expect(viewModel.selectedBundle?.id == folder.id)
    }

    @Test("contentsText for a category fetches and formats its threads")
    func contentsText_category_formatsThreads() async {
        let category = NewsBundle(
            identifier: Data([0x00, 0x00, 0x00, 0x01]),
            title: "News",
            kind: .category
        )
        let post = NewsThread(
            threadID: 1,
            parentID: 0,
            postDate: Self.fixedDate,
            elements: [ThreadElement(title: "Hi", author: "a", body: "body")]
        )
        let viewModel = ThreadedNewsViewModel(
            fetchBundles: { _ in [category] },
            fetchThreads: { _ in [post] },
            fetchThread: { _, threadID, _ in NewsThread(threadID: threadID) },
            createBundleAt: { _, _, _ in },
            postThread: { _, _, _, _, _ in },
            deleteBundleAt: { _ in },
            deleteThreadAt: { _, _, _ in }
        )
        let text = await viewModel.contentsText(for: category)
        let expected = NewsClipboardFormatter.formatBundleContents(
            sections: [(heading: "News", threads: [post])]
        )
        #expect(text == expected)
    }

    @Test("contentsText for a folder recurses its categories with plain headings")
    func contentsText_folder_recursesCategories() async {
        let folder = NewsBundle(
            identifier: Data([0x00, 0x00, 0x00, 0x01]),
            title: "Folder",
            kind: .bundle
        )
        let catA = NewsBundle(
            identifier: Data([0x00, 0x00, 0x00, 0x02]),
            title: "A",
            kind: .category
        )
        let catB = NewsBundle(
            identifier: Data([0x00, 0x00, 0x00, 0x03]),
            title: "B",
            kind: .category
        )
        let postA = NewsThread(
            threadID: 1,
            parentID: 0,
            postDate: Self.fixedDate,
            elements: [ThreadElement(title: "Pa", author: "a", body: "a")]
        )
        let postB = NewsThread(
            threadID: 2,
            parentID: 0,
            postDate: Self.fixedDate,
            elements: [ThreadElement(title: "Pb", author: "b", body: "b")]
        )
        let viewModel = ThreadedNewsViewModel(
            fetchBundles: { path in
                path.components == ["Folder"] ? [catA, catB] : [folder]
            },
            fetchThreads: { path in
                if path.components == ["Folder", "A"] { return [postA] }
                if path.components == ["Folder", "B"] { return [postB] }
                return []
            },
            fetchThread: { _, threadID, _ in NewsThread(threadID: threadID) },
            createBundleAt: { _, _, _ in },
            postThread: { _, _, _, _, _ in },
            deleteBundleAt: { _ in },
            deleteThreadAt: { _, _, _ in }
        )
        let text = await viewModel.contentsText(for: folder)
        #expect(text?.contains("## A") == true)
        #expect(text?.contains("## B") == true)
        #expect(text?.contains("Subject: Pa") == true)
        #expect(text?.contains("Subject: Pb") == true)
    }

    @Test("contentsText path-qualifies headings inside a nested folder")
    func contentsText_nestedFolder_qualifiedHeading() async {
        let folder = NewsBundle(
            identifier: Data([0x00, 0x00, 0x00, 0x01]),
            title: "Folder",
            kind: .bundle
        )
        let subfolder = NewsBundle(
            identifier: Data([0x00, 0x00, 0x00, 0x02]),
            title: "Sub",
            kind: .bundle
        )
        let category = NewsBundle(
            identifier: Data([0x00, 0x00, 0x00, 0x03]),
            title: "Cat",
            kind: .category
        )
        let post = NewsThread(
            threadID: 1,
            parentID: 0,
            postDate: Self.fixedDate,
            elements: [ThreadElement(title: "Deep", author: "a", body: "x")]
        )
        let viewModel = ThreadedNewsViewModel(
            fetchBundles: { path in
                switch path.components {
                case ["Folder"]:
                    return [subfolder]
                case ["Folder", "Sub"]:
                    return [category]
                default:
                    return [folder]
                }
            },
            fetchThreads: { path in
                path.components == ["Folder", "Sub", "Cat"] ? [post] : []
            },
            fetchThread: { _, threadID, _ in NewsThread(threadID: threadID) },
            createBundleAt: { _, _, _ in },
            postThread: { _, _, _, _, _ in },
            deleteBundleAt: { _ in },
            deleteThreadAt: { _, _, _ in }
        )
        let text = await viewModel.contentsText(for: folder)
        #expect(text?.contains("## Sub / Cat") == true)
    }

    @Test("contentsText for an empty folder returns nil")
    func contentsText_emptyFolder_returnsNil() async {
        let folder = NewsBundle(
            identifier: Data([0x00, 0x00, 0x00, 0x01]),
            title: "Folder",
            kind: .bundle
        )
        let viewModel = ThreadedNewsViewModel(
            fetchBundles: { path in path.components == ["Folder"] ? [] : [folder] },
            fetchThreads: { _ in [] },
            fetchThread: { _, threadID, _ in NewsThread(threadID: threadID) },
            createBundleAt: { _, _, _ in },
            postThread: { _, _, _, _, _ in },
            deleteBundleAt: { _ in },
            deleteThreadAt: { _, _, _ in }
        )
        #expect(await viewModel.contentsText(for: folder) == nil)
    }

    @Test("contentsText presents an error and returns nil when a fetch throws")
    func contentsText_fetchThrows_presentsError() async {
        let category = NewsBundle(
            identifier: Data([0x00, 0x00, 0x00, 0x01]),
            title: "News",
            kind: .category
        )
        let errors = PresentedErrorRecorder()
        let viewModel = ThreadedNewsViewModel(
            fetchBundles: { _ in [category] },
            fetchThreads: { _ in throw StubFetchError() },
            fetchThread: { _, threadID, _ in NewsThread(threadID: threadID) },
            createBundleAt: { _, _, _ in },
            postThread: { _, _, _, _, _ in },
            deleteBundleAt: { _ in },
            deleteThreadAt: { _, _, _ in },
            present: { errors.record($0) }
        )
        let text = await viewModel.contentsText(for: category)
        #expect(text == nil)
        #expect(errors.last != nil)
        #expect(viewModel.isGatheringCopy == false)
    }

    @Test("isGatheringCopy is false after a successful gather")
    func isGatheringCopy_falseAfterCompletion() async {
        let category = NewsBundle(
            identifier: Data([0x00, 0x00, 0x00, 0x01]),
            title: "News",
            kind: .category
        )
        let viewModel = ThreadedNewsViewModel(
            fetchBundles: { _ in [category] },
            fetchThreads: { _ in [] },
            fetchThread: { _, threadID, _ in NewsThread(threadID: threadID) },
            createBundleAt: { _, _, _ in },
            postThread: { _, _, _, _, _ in },
            deleteBundleAt: { _ in },
            deleteThreadAt: { _, _, _ in }
        )
        _ = await viewModel.contentsText(for: category)
        #expect(viewModel.isGatheringCopy == false)
    }
}
