import SwiftUI
import AppKit

/// Persist `HSplitView` / `VSplitView` divider positions to
/// `UserDefaults` so they survive both feature switches inside one
/// session AND app relaunches.
///
/// Why not `NSSplitView.autosaveName`? SwiftUI realizes its split views
/// late, so by the time we can reach into the AppKit `NSSplitView`,
/// it has already laid out — the built-in restore-on-load step has
/// passed. We set the divider positions ourselves on first show and
/// then mirror every user-driven resize to `UserDefaults` via the
/// `NSSplitView.didResizeSubviewsNotification` notification.
///
/// Usage — drop into one of the SwiftUI panes via `.background` so the
/// helper view sits *inside* the NSSplitView and can find it via
/// `superview` walk:
///
/// ```swift
/// HSplitView {
///     leftPane.background(SplitViewAutosaver(name: "Heidrun.news.bundles"))
///     rightPane
/// }
/// ```
public struct SplitViewAutosaver: NSViewRepresentable {
    let name: String

    public init(name: String) {
        self.name = name
    }

    public func makeNSView(context: Context) -> NSView { AutosaverNSView(autosaveKey: name) }

    public func updateNSView(_ nsView: NSView, context: Context) {
        // Name is immutable per instance — no update needed.
    }
}

/// Hidden zero-size NSView that owns the divider-position autosave hook.
/// On window-attach it walks its superview chain to the enclosing
/// `NSSplitView`, restores the saved positions, and subscribes to that
/// split view's resize notification to write them back as the user
/// drags.
private final class AutosaverNSView: NSView {
    private let autosaveKey: String
    private weak var observedSplitView: NSSplitView?
    private var resizeObserver: NSObjectProtocol?

    init(autosaveKey: String) {
        self.autosaveKey = autosaveKey
        super.init(frame: .zero)
        // We deliberately stay zero-sized + invisible.
        self.isHidden = true
        self.translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not implemented for AutosaverNSView")
    }

    // Cleanup happens in `viewDidMoveToWindow(nil)` rather than deinit
    // because in Swift 6 the deinit on a MainActor-isolated NSView is
    // nonisolated and can't touch the observer token. The window-detach
    // path is the only realistic teardown for this view anyway.

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            // Detached — drop the subscription so we don't leak across
            // window teardown.
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
                self.resizeObserver = nil
            }
            observedSplitView = nil
            return
        }

        // SwiftUI realises split views over several layout passes — the
        // enclosing NSSplitView may not yet have its arrangedSubviews
        // when we first see a window. Keep retrying on the run loop
        // until we find one with the dividers we expect to autosave.
        installAutosaveHook(retriesLeft: 30)
    }

    private func installAutosaveHook(retriesLeft: Int) {
        guard observedSplitView == nil else { return }
        let splitView = enclosingSplitView()
        let dividerCount = splitView.map { max(0, $0.arrangedSubviews.count - 1) } ?? 0
        // Wait until the split view has at least one divider — until
        // both arrangedSubviews exist, `setPosition` and the resize
        // notification are pointless.
        guard let splitView, dividerCount > 0 else {
            if retriesLeft > 0 {
                DispatchQueue.main.async { [weak self] in
                    self?.installAutosaveHook(retriesLeft: retriesLeft - 1)
                }
            }
            return
        }
        observedSplitView = splitView
        restorePositions(into: splitView)
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification,
            object: splitView,
            queue: .main
        ) { [weak self, weak splitView] notification in
            // NSSplitView posts this for layout-driven resizes too
            // (SwiftUI relayout, window resize, content size change).
            // Saving on those overwrites the user's drag with the
            // post-layout default the next moment — divider feels
            // stuck. The `NSSplitViewDividerIndex` key in userInfo is
            // present ONLY when the user actually dragged a divider,
            // so gate the save on that.
            //
            // Pull the bool out of `notification` BEFORE the actor hop
            // — `Notification` isn't Sendable under Swift 6.
            let wasUserDrag = notification.userInfo?["NSSplitViewDividerIndex"] != nil
            // `queue: .main` guarantees we're on the main thread; tell
            // the compiler so it lets us touch MainActor state.
            MainActor.assumeIsolated {
                guard wasUserDrag, let self, let splitView else { return }
                self.savePositions(from: splitView)
            }
        }
        // Re-apply the restored position on the next run-loop pass so
        // SwiftUI's `idealHeight` / `idealWidth` preference, if any,
        // can't snap the divider back after our first `setPosition`.
        DispatchQueue.main.async { [weak self, weak splitView] in
            guard let self, let splitView else { return }
            self.restorePositions(into: splitView)
        }
    }

    private func enclosingSplitView() -> NSSplitView? {
        var current: NSView? = self.superview
        while let view = current {
            if let splitView = view as? NSSplitView { return splitView }
            current = view.superview
        }
        return nil
    }

    private var defaultsKey: String { "Heidrun.SplitViewAutosave.\(autosaveKey)" }

    private func restorePositions(into splitView: NSSplitView) {
        guard let stored = UserDefaults.standard.array(forKey: defaultsKey) as? [Double] else { return }
        // Only restore when the divider count matches what we stored —
        // otherwise `setPosition` would touch dividers that don't exist.
        let dividerCount = max(0, splitView.arrangedSubviews.count - 1)
        guard stored.count == dividerCount else { return }
        for (dividerIndex, position) in stored.enumerated() {
            splitView.setPosition(CGFloat(position), ofDividerAt: dividerIndex)
        }
    }

    private func savePositions(from splitView: NSSplitView) {
        let dividerCount = max(0, splitView.arrangedSubviews.count - 1)
        guard dividerCount > 0 else { return }
        var positions: [Double] = []
        var cursor: CGFloat = 0
        for index in 0..<dividerCount {
            let subview = splitView.arrangedSubviews[index]
            let dimension = splitView.isVertical ? subview.frame.width : subview.frame.height
            cursor += dimension
            positions.append(Double(cursor))
            cursor += splitView.dividerThickness
        }
        UserDefaults.standard.set(positions, forKey: defaultsKey)
    }
}
