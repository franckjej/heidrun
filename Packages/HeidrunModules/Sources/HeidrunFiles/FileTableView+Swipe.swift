import AppKit
import HeidrunCore

extension FileTableView {
    /// Back/forward/up + swipe-slide callbacks for the list.
    @MainActor
    static func wireNavigation(_ tableView: FileShortcutTableView, to coordinator: Coordinator) {
        tableView.onBack = { [weak coordinator] in coordinator?.parent.actions.goBack() }
        tableView.onForward = { [weak coordinator] in coordinator?.parent.actions.goForward() }
        tableView.onUp = { [weak coordinator] in coordinator?.parent.actions.navigateUp() }
        let tracker = tableView.swipeTracker
        tracker.canGoBack = { [weak coordinator] in coordinator?.parent.actions.backTarget() != nil }
        tracker.canGoForward = { [weak coordinator] in coordinator?.parent.actions.forwardTarget() != nil }
        tracker.onBack = { [weak coordinator] in coordinator?.parent.actions.goBack() }
        tracker.onForward = { [weak coordinator] in coordinator?.parent.actions.goForward() }
        tracker.onSwipeBegan = { [weak coordinator] in coordinator?.swipeBegan() }
        tracker.onSwipeChanged = { [weak coordinator] amount in coordinator?.container?.updateSlide(amount: amount) }
        tracker.onSwipeFinished = { [weak coordinator] in coordinator?.container?.endSlide() }
    }
}

extension FileTableView.Coordinator {
    /// Before the rows of a newly-shown folder go in: remember how the
    /// outgoing folder looked, where it was scrolled and what was selected.
    func pathWillChange(to newPath: RemotePath) {
        if let container, let tableView {
            snapshots.store(
                container.capturePage(),
                offset: container.scrollView.contentView.bounds.origin,
                selection: FileSelectionMapping.selection(forRows: tableView.selectedRowIndexes, in: files),
                for: displayedPath
            )
        }
        displayedPath = newPath
        awaitingListing = true
    }

    /// Once the new folder's rows are in, bring back what was selected
    /// there. The binding is written next turn (not mid view update);
    /// `pendingSelection` stands in until then.
    func restoreSelection() {
        guard awaitingListing else { return }
        awaitingListing = false
        let restored = snapshots.selection(for: displayedPath).intersection(files.map(\.id))
        pendingSelection = restored
        Task { @MainActor [weak self] in
            guard let self, pendingSelection == restored else { return }
            parent.selection = restored
            pendingSelection = nil
        }
    }

    /// Scroll the newly-shown folder to where it was left, else the top.
    func restoreScrollPosition() {
        guard let scrollView = container?.scrollView, let tableView else { return }
        tableView.tile()
        let clipView = scrollView.contentView
        let target = snapshots.offset(for: displayedPath)
            ?? NSPoint(x: 0, y: -scrollView.contentInsets.top)
        let constrained = clipView.constrainBoundsRect(NSRect(origin: target, size: clipView.bounds.size))
        clipView.setBoundsOrigin(constrained.origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    func swipeBegan() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let container else { return }
        container.beginSlide(
            back: parent.actions.backTarget().flatMap { snapshots.snapshot(for: $0) },
            forward: parent.actions.forwardTarget().flatMap { snapshots.snapshot(for: $0) }
        )
    }
}
