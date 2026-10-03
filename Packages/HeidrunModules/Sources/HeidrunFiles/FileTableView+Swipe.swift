import AppKit
import HeidrunCore

extension FileTableView {
    /// Back/forward/up + swipe-slide callbacks for the list.
    @MainActor
    static func wireNavigation(_ tableView: FileShortcutTableView, to coordinator: Coordinator) {
        tableView.onBack = { [weak coordinator] in coordinator?.parent.actions.goBack() }
        tableView.onForward = { [weak coordinator] in coordinator?.parent.actions.goForward() }
        tableView.onUp = { [weak coordinator] in coordinator?.parent.actions.navigateUp() }
        tableView.canGoBack = { [weak coordinator] in coordinator?.parent.actions.backTarget() != nil }
        tableView.canGoForward = { [weak coordinator] in coordinator?.parent.actions.forwardTarget() != nil }
        tableView.onSwipeBegan = { [weak coordinator] in coordinator?.swipeBegan() }
        tableView.onSwipeChanged = { [weak coordinator] amount in coordinator?.container?.updateSlide(amount: amount) }
        tableView.onSwipeFinished = { [weak coordinator] in coordinator?.container?.endSlide() }
    }
}

extension FileTableView.Coordinator {
    /// Before the rows of a newly-shown folder go in: remember how the
    /// outgoing folder looked and where it was scrolled.
    func pathWillChange(to newPath: RemotePath) {
        if let container {
            snapshots.store(
                container.capturePage(),
                offset: container.scrollView.contentView.bounds.origin,
                for: displayedPath
            )
        }
        displayedPath = newPath
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
