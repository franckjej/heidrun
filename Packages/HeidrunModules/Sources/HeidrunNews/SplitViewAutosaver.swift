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
struct SplitViewAutosaver: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView { AutosaverNSView(autosaveKey: name) }

    func updateNSView(_ nsView: NSView, context: Context) {
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

        // SwiftUI may install us before the enclosing NSSplitView has
        // finished arranging its children. Defer to next run-loop so
        // `setPosition` lands on the final layout, not a transient one.
        DispatchQueue.main.async { [weak self] in
            self?.installAutosaveHook()
        }
    }

    private func installAutosaveHook() {
        guard observedSplitView == nil, let splitView = enclosingSplitView() else { return }
        observedSplitView = splitView
        restorePositions(into: splitView)
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSSplitView.didResizeSubviewsNotification,
            object: splitView,
            queue: .main
        ) { [weak self, weak splitView] _ in
            // `queue: .main` guarantees we're on the main thread; tell
            // the compiler so it lets us touch MainActor state.
            MainActor.assumeIsolated {
                guard let self, let splitView else { return }
                self.savePositions(from: splitView)
            }
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
