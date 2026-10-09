import Foundation
import HeidrunCore

/// Where threaded news is: the left-pane folder, the folder/category
/// selected in it, and the open thread.
public struct NewsLocation: Hashable, Sendable {
    public var path: RemotePath
    public var bundleID: NewsBundle.ID?
    public var threadID: UInt16?

    public init(path: RemotePath, bundleID: NewsBundle.ID? = nil, threadID: UInt16? = nil) {
        self.path = path
        self.bundleID = bundleID
        self.threadID = threadID
    }
}

/// Body-cache key: a thread in a category.
struct NewsThreadKey: Hashable {
    let categoryPath: RemotePath
    let threadID: UInt16
}

extension ThreadedNewsViewModel {
    public var currentLocation: NewsLocation {
        NewsLocation(path: currentPath, bundleID: selectedBundleID, threadID: selectedThreadID)
    }

    public var canGoBack: Bool { !backStack.isEmpty }
    public var canGoForward: Bool { !forwardStack.isEmpty }
    public var backTarget: NewsLocation? { backStack.last }
    public var forwardTarget: NewsLocation? { forwardStack.last }

    public func goBack() async {
        guard let previous = backStack.popLast() else { return }
        let origin = currentLocation
        onWillLeaveLocation?(origin)
        forwardStack.append(origin)
        await show(previous)
    }

    public func goForward() async {
        guard let next = forwardStack.popLast() else { return }
        let origin = currentLocation
        onWillLeaveLocation?(origin)
        backStack.append(origin)
        await show(next)
    }

    /// Before moving to `target`: record the current location as a step
    /// (clearing forward), unless replacing it or staying put.
    func recordHistory(toward target: NewsLocation, replacing: Bool) {
        let origin = currentLocation
        guard !replacing, target != origin else { return }
        onWillLeaveLocation?(origin)
        backStack.append(origin)
        forwardStack.removeAll()
    }

    /// Show `location` from the caches at once, then refresh it. A
    /// category or thread gone since lands on its folder / category.
    func show(_ location: NewsLocation) async {
        currentPath = location.path
        bundles = bundlesCache[location.path] ?? []
        selectedBundleID = location.bundleID
        let categoryPath = selectedCategoryPath
        threads = categoryPath.flatMap { threadsCache[$0] } ?? []
        selectedThreadID = location.threadID
        if let categoryPath, let threadID = location.threadID {
            loadedThread = bodyCache[NewsThreadKey(categoryPath: categoryPath, threadID: threadID)]
        } else {
            loadedThread = nil
        }

        await refreshBundles()
        guard currentLocation == location else { return }
        if let bundleID = location.bundleID, !bundles.contains(where: { $0.id == bundleID }) {
            selectedBundleID = nil
            clearThreadState()
            return
        }
        guard let categoryPath else { return }
        await loadThreads(at: categoryPath)
        guard currentLocation == location, let threadID = location.threadID else { return }
        guard let thread = threads.first(where: { $0.threadID == threadID }) else {
            selectedThreadID = nil
            loadedThread = nil
            return
        }
        await openThread(threadID: threadID, type: thread.elements.first?.mimeType ?? ThreadElement.plainTextType)
    }
}
