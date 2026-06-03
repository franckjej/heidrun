import Foundation
import Observation
import HeidrunCore

public enum CopyScope: Sendable {
    /// Selected thread's first element only (subject + author + date + body).
    case post
    /// Selected thread plus every descendant by `parentID`.
    case thread
}

/// 3-pane threaded-news model: left pane lists bundles at `currentPath`;
/// right top lists `threads` under the selected category; right bottom
/// shows the loaded body for the selected thread. Folders are fetched
/// with TX 370; categories use TX 371 for the thread list and TX 400 for
/// an individual thread body.
@Observable
@MainActor
public final class ThreadedNewsViewModel {
    // MARK: - Left pane

    /// Selecting a category KEEPS `currentPath` where it is so the user
    /// can flip between sibling categories without re-navigating.
    public private(set) var currentPath: RemotePath = []

    public private(set) var bundles: [NewsBundle] = []
    public private(set) var selectedBundleID: NewsBundle.ID?

    // MARK: - Right pane

    public private(set) var threads: [NewsThread] = []
    public private(set) var selectedThreadID: UInt16?

    /// Reads from `threads` (not `loadedThread`) so a top-level / empty-
    /// body post is fully actionable the moment its row is selected —
    /// no body fetch needed.
    public var selectedThread: NewsThread? {
        guard let id = selectedThreadID else { return nil }
        return threads.first { $0.threadID == id }
    }

    public private(set) var loadedThread: NewsThread?

    /// Prefer `loadedThread` (TX 400, carries the body) when it matches
    /// the current selection; fall back to the list metadata (TX 371).
    /// Without the preference the edit sheet would receive a body-less
    /// entry and overwrite the post with empty body on Save.
    public var editableSelectedThread: NewsThread? {
        guard let identifier = selectedThreadID else { return nil }
        if let loaded = loadedThread, loaded.threadID == identifier {
            return loaded
        }
        return threads.first { $0.threadID == identifier }
    }

    // MARK: - Status

    public private(set) var isLoadingBundles: Bool = false
    public private(set) var isLoadingThreads: Bool = false
    public private(set) var isLoadingBody: Bool = false
    public private(set) var lastError: String?

    /// True while a folder/category Copy-Contents gather is in flight.
    public private(set) var isGatheringCopy: Bool = false

    public var isLoading: Bool { isLoadingBundles || isLoadingThreads || isLoadingBody }

    public var selectedCategoryPath: RemotePath? {
        guard let id = selectedBundleID, id.kind == .category else { return nil }
        return currentPath.appending(id.title)
    }

    public var selectedBundle: NewsBundle? {
        guard let identifier = selectedBundleID else { return nil }
        return bundles.first { bundle in bundle.id == identifier }
    }

    private let fetchBundles: @Sendable (RemotePath) async throws -> [NewsBundle]
    private let fetchThreads: @Sendable (RemotePath) async throws -> [NewsThread]
    private let fetchThread: @Sendable (RemotePath, UInt16, String) async throws -> NewsThread
    private let createBundleAt: @Sendable (RemotePath, String, Bool) async throws -> Void
    private let postThread: @Sendable (RemotePath, UInt16, String, String, String) async throws -> Void
    private let deleteBundleAt: @Sendable (RemotePath) async throws -> Void
    private let deleteThreadAt: @Sendable (RemotePath, UInt16, Bool) async throws -> Void

    public init(
        fetchBundles: @escaping @Sendable (RemotePath) async throws -> [NewsBundle],
        fetchThreads: @escaping @Sendable (RemotePath) async throws -> [NewsThread],
        fetchThread: @escaping @Sendable (RemotePath, UInt16, String) async throws -> NewsThread,
        createBundleAt: @escaping @Sendable (RemotePath, String, Bool) async throws -> Void,
        postThread: @escaping @Sendable (RemotePath, UInt16, String, String, String) async throws -> Void,
        deleteBundleAt: @escaping @Sendable (RemotePath) async throws -> Void,
        deleteThreadAt: @escaping @Sendable (RemotePath, UInt16, Bool) async throws -> Void
    ) {
        self.fetchBundles    = fetchBundles
        self.fetchThreads    = fetchThreads
        self.fetchThread     = fetchThread
        self.createBundleAt  = createBundleAt
        self.postThread      = postThread
        self.deleteBundleAt  = deleteBundleAt
        self.deleteThreadAt  = deleteThreadAt
    }

    public convenience init(client: any HotlineClient) {
        self.init(
            fetchBundles: { [client] path in
                try await client.fetchNewsBundles(at: path)
            },
            fetchThreads: { [client] path in
                try await client.fetchNewsThreads(at: path)
            },
            fetchThread: { [client] path, threadID, type in
                try await client.fetchNewsThread(at: path, threadID: threadID, type: type)
            },
            createBundleAt: { [client] path, name, isCategory in
                try await client.createNewsBundle(at: path, name: name, isCategory: isCategory)
            },
            postThread: { [client] path, parentID, title, type, body in
                try await client.postNewsThread(
                    at: path,
                    parentThreadID: parentID,
                    title: title,
                    type: type,
                    body: body
                )
            },
            deleteBundleAt: { [client] path in
                try await client.deleteNewsBundle(at: path)
            },
            deleteThreadAt: { [client] path, threadID, cascade in
                try await client.deleteNewsThread(at: path, threadID: threadID, cascade: cascade)
            }
        )
    }

    // MARK: - Navigation

    /// Single-tap: categories load threads into the right pane; folders
    /// just highlight without descending (descent requires `descend` /
    /// double-click). Matches Finder semantics so a freshly-created empty
    /// folder doesn't make the user feel like they lost their work.
    public func select(_ bundle: NewsBundle) async {
        selectedBundleID = bundle.id
        clearThreadState()
        if bundle.kind == .category {
            await loadThreads(at: currentPath.appending(bundle.title))
        }
    }

    /// Double-tap on a folder. No-op for categories (terminal nodes).
    public func descend(into bundle: NewsBundle) async {
        guard bundle.kind == .bundle else { return }
        currentPath = currentPath.appending(bundle.title)
        selectedBundleID = nil
        clearThreadState()
        await refreshBundles()
    }

    public func navigateUp() async {
        guard !currentPath.isRoot else { return }
        currentPath = currentPath.parent
        selectedBundleID = nil
        clearThreadState()
        await refreshBundles()
    }

    /// Truncate `currentPath` to the first `depth` components. `0` lands
    /// on root. Driven by breadcrumb taps.
    public func navigate(toDepth depth: Int) async {
        let count = currentPath.components.count
        guard depth >= 0, depth < count else { return }
        currentPath = RemotePath(components: Array(currentPath.components.prefix(depth)))
        selectedBundleID = nil
        clearThreadState()
        await refreshBundles()
    }

    public func refresh() async {
        if let path = selectedCategoryPath {
            await loadThreads(at: path)
        } else {
            await refreshBundles()
        }
    }

    private func refreshBundles() async {
        isLoadingBundles = true
        defer { isLoadingBundles = false }
        do {
            bundles = try await fetchBundles(currentPath)
            lastError = nil
        } catch {
            lastError = String(describing: error)
            bundles = []
        }
    }

    private func loadThreads(at path: RemotePath) async {
        isLoadingThreads = true
        defer { isLoadingThreads = false }
        do {
            threads = try await fetchThreads(path)
            lastError = nil
        } catch {
            lastError = String(describing: error)
            threads = []
        }
    }

    // MARK: - Thread bodies

    public func openThread(_ thread: NewsThread) async {
        selectedThreadID = thread.threadID
        let mime = thread.elements.first?.mimeType ?? ThreadElement.plainTextType
        await openThread(threadID: thread.threadID, type: mime)
    }

    public func openThread(threadID: UInt16, type: String = ThreadElement.plainTextType) async {
        guard let path = selectedCategoryPath else { return }
        selectedThreadID = threadID
        isLoadingBody = true
        defer { isLoadingBody = false }
        do {
            loadedThread = try await fetchThread(path, threadID, type)
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
    }

    public func dismissLoadedThread() {
        loadedThread = nil
        selectedThreadID = nil
    }

    // MARK: - Mutations

    public func createBundle(named name: String, isCategory: Bool) async {
        do {
            try await createBundleAt(currentPath, name, isCategory)
            await refreshBundles()
        } catch {
            lastError = String(describing: error)
        }
    }

    public func post(
        parentThreadID: UInt16 = 0,
        title: String,
        type: String = ThreadElement.plainTextType,
        body: String
    ) async {
        guard let path = selectedCategoryPath else { return }
        do {
            try await postThread(path, parentThreadID, title, type, body)
            await loadThreads(at: path)
        } catch {
            lastError = String(describing: error)
        }
    }

    public func deleteBundle() async {
        do {
            try await deleteBundleAt(currentPath)
            await navigateUp()
        } catch {
            lastError = String(describing: error)
        }
    }

    /// Delete a left-pane bundle without first navigating into it. Path
    /// is `currentPath + bundle.title`, matching `select` / `descend`.
    public func deleteBundle(_ bundle: NewsBundle) async {
        let targetPath = currentPath.appending(bundle.title)
        do {
            try await deleteBundleAt(targetPath)
            if selectedBundleID == bundle.id {
                selectedBundleID = nil
                clearThreadState()
            }
            await refreshBundles()
        } catch {
            lastError = String(describing: error)
        }
    }

    public func deleteThread(threadID: UInt16, cascade: Bool) async {
        guard let path = selectedCategoryPath else { return }
        do {
            try await deleteThreadAt(path, threadID, cascade)
            if selectedThreadID == threadID { dismissLoadedThread() }
            await loadThreads(at: path)
        } catch {
            lastError = String(describing: error)
        }
    }

    /// Edit by deleting (cascade: false so replies survive as orphans)
    /// and reposting at the same `parentID`. Hotline has no direct edit
    /// transaction, so the new post gets a fresh `threadID`. If the
    /// delete succeeds and the repost throws, the original is gone and
    /// the new one isn't written — no safe undo.
    public func editThread(
        threadID: UInt16,
        newTitle: String,
        newBody: String,
        type: String = ThreadElement.plainTextType
    ) async {
        guard let path = selectedCategoryPath,
              let original = threads.first(where: { $0.threadID == threadID })
        else { return }
        let parentID = original.parentID
        do {
            try await deleteThreadAt(path, threadID, false)
            try await postThread(path, parentID, newTitle, type, newBody)
            await loadThreads(at: path)
            lastError = nil
        } catch {
            // Refresh FIRST so the tree reflects true server state
            // (delete may have succeeded even though the repost threw),
            // THEN set lastError — loadThreads clears it on success, so
            // writing the error after makes it stick.
            await loadThreads(at: path)
            lastError = String(describing: error)
        }
    }

    // MARK: - Clipboard

    public func copyText(threadID: UInt16, scope: CopyScope) -> String? {
        guard let target = threads.first(where: { $0.threadID == threadID })
        else { return nil }
        switch scope {
        case .post:
            return NewsClipboardFormatter.formatPost(target)
        case .thread:
            return NewsClipboardFormatter.formatThread(target, descendantsFrom: threads)
        }
    }

    /// Plain-text rendering of a bundle's content for the pasteboard. A
    /// category fetches its own threads; a folder recurses every sub-
    /// category (and sub-folder) and groups each under a `## heading`.
    /// Always fetches fresh — the target may differ from selection.
    public func contentsText(for bundle: NewsBundle) async -> String? {
        isGatheringCopy = true
        defer { isGatheringCopy = false }
        let bundlePath = currentPath.appending(bundle.title)
        do {
            let sections: [(heading: String, threads: [NewsThread])]
            switch bundle.kind {
            case .category:
                let threads = try await fetchThreads(bundlePath)
                sections = [(heading: bundle.title, threads: threads)]
            case .bundle:
                sections = try await gatherSections(at: bundlePath, headingPrefix: "")
            }
            lastError = nil
            guard !sections.isEmpty else { return nil }
            return NewsClipboardFormatter.formatBundleContents(sections: sections)
        } catch {
            lastError = String(describing: error)
            return nil
        }
    }

    /// `headingPrefix` accumulates the path relative to the copied folder
    /// so a category inside a sub-folder reads as `"Sub / Category"`.
    private func gatherSections(
        at path: RemotePath,
        headingPrefix: String
    ) async throws -> [(heading: String, threads: [NewsThread])] {
        let children = try await fetchBundles(path)
        var sections: [(heading: String, threads: [NewsThread])] = []
        for child in children {
            let childPath = path.appending(child.title)
            switch child.kind {
            case .category:
                let threads = try await fetchThreads(childPath)
                sections.append((heading: headingPrefix + child.title, threads: threads))
            case .bundle:
                let nested = try await gatherSections(
                    at: childPath,
                    headingPrefix: headingPrefix + child.title + " / "
                )
                sections.append(contentsOf: nested)
            }
        }
        return sections
    }

    // MARK: - Private helpers

    private func clearThreadState() {
        threads = []
        selectedThreadID = nil
        loadedThread = nil
    }
}
