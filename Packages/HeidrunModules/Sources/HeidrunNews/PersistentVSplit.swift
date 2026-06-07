import SwiftUI
import AppKit

/// AppKit-backed vertical split-pane wrapper for SwiftUI. We use this
/// instead of SwiftUI's `VSplitView` for two reasons:
///
///   1. SwiftUI's `VSplitView` re-arranges its children on every layout
///      pass based on ideal / intrinsic sizes. The moment the bottom
///      pane's content changes (e.g. a thread body loads where there
///      was a "No Thread Selected" empty state), SwiftUI snaps the
///      divider back to its computed default. `setPosition` from a
///      side-channel autosaver can't out-race that — the divider keeps
///      jumping the instant the user clicks a row.
///   2. `NSSplitView.autosaveName` is bullet-proof: it tracks user
///      drags natively, writes to `UserDefaults` under a stable key,
///      and restores on the first layout of the next launch. Pairing
///      it with `holdingPriority = .defaultLow` on both panes means
///      the divider stays where the user left it regardless of what
///      the SwiftUI content inside the panes is doing.
///
/// The two panes are hosted via `NSHostingController<AnyView>`; we
/// re-assign `rootView` in `updateNSViewController` so SwiftUI re-
/// renders propagate into the hosted children.
struct PersistentVSplit: NSViewControllerRepresentable {
    let autosaveName: String
    let topMinHeight: CGFloat
    let bottomMinHeight: CGFloat
    /// Position the divider snaps to on double-click, measured as the
    /// height of the top pane in points. Matches the "ideal" default
    /// the SwiftUI version used to use.
    let defaultTopHeight: CGFloat
    let top: AnyView
    let bottom: AnyView

    init<Top: View, Bottom: View>(
        autosaveName: String,
        topMinHeight: CGFloat,
        bottomMinHeight: CGFloat,
        defaultTopHeight: CGFloat,
        @ViewBuilder top: () -> Top,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self.autosaveName = autosaveName
        self.topMinHeight = topMinHeight
        self.bottomMinHeight = bottomMinHeight
        self.defaultTopHeight = defaultTopHeight
        self.top = AnyView(top())
        self.bottom = AnyView(bottom())
    }

    func makeNSViewController(context: Context) -> PersistentSplitViewController {
        let controller = PersistentSplitViewController(defaultTopHeight: defaultTopHeight)
        controller.splitView.isVertical = false
        controller.splitView.dividerStyle = .thin
        // Native NSSplitView autosave: writes divider positions to
        // UserDefaults under "NSSplitView Subview Frames {autosaveName}".
        // Tracks user drags only — layout-driven resizes don't overwrite.
        controller.splitView.autosaveName = autosaveName

        let topItem = NSSplitViewItem(viewController: NSHostingController(rootView: top))
        topItem.minimumThickness = topMinHeight
        topItem.canCollapse = false
        // `.defaultLow` on both → the divider, not the panes, owns the
        // split; content-size changes inside either pane can't bump it.
        topItem.holdingPriority = .defaultLow
        controller.addSplitViewItem(topItem)

        let bottomItem = NSSplitViewItem(viewController: NSHostingController(rootView: bottom))
        bottomItem.minimumThickness = bottomMinHeight
        bottomItem.canCollapse = false
        bottomItem.holdingPriority = .defaultLow
        controller.addSplitViewItem(bottomItem)

        return controller
    }

    func updateNSViewController(_ controller: PersistentSplitViewController, context: Context) {
        guard controller.splitViewItems.count == 2 else { return }
        if let topHost = controller.splitViewItems[0].viewController as? NSHostingController<AnyView> {
            topHost.rootView = top
        }
        if let bottomHost = controller.splitViewItems[1].viewController as? NSHostingController<AnyView> {
            bottomHost.rootView = bottom
        }
    }
}

/// NSSplitViewController that snaps the divider to `defaultTopHeight`
/// when the user double-clicks it. Wires up an `NSClickGestureRecognizer`
/// (numberOfClicksRequired = 2) on the splitView in `viewDidLoad`.
///
/// Why not the legacy `splitView(_:shouldCollapseSubview:
/// forDoubleClickOnDividerAt:)` delegate? Under `NSSplitViewController`
/// collapse is owned by `NSSplitViewItem.canCollapse`; the legacy
/// double-click delegate isn't called in this hierarchy. A gesture
/// recogniser is the modern AppKit equivalent — no `mouseDown`
/// hijacking, no `NSSplitView` subclass.
final class PersistentSplitViewController: NSSplitViewController, NSGestureRecognizerDelegate {
    private let defaultTopHeight: CGFloat

    init(defaultTopHeight: CGFloat) {
        self.defaultTopHeight = defaultTopHeight
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let recogniser = NSClickGestureRecognizer(
            target: self,
            action: #selector(handleDoubleClick(_:))
        )
        recogniser.numberOfClicksRequired = 2
        // Delay primary mouse-button events so NSSplitView's divider
        // tracking loop doesn't swallow the first mouseDown before we
        // can tell whether it's the start of a double-click. With
        // `false` the first click starts a drag immediately and we
        // never get to recognise the second.
        //
        // CRITICAL: this delay is gated by the system double-click
        // interval, and the recogniser spans the WHOLE split view — so
        // without the delegate gate below it withholds EVERY click in
        // both panes for that interval before the NSOutlineView (and any
        // other content) ever sees the mouseDown. `shouldAttemptTo
        // RecognizeWith` returns false for non-divider clicks, letting
        // content clicks through with zero latency; only divider clicks
        // pay the double-click wait.
        recogniser.delaysPrimaryMouseButtonEvents = true
        recogniser.delegate = self
        splitView.addGestureRecognizer(recogniser)
    }

    /// Only let the double-click recogniser engage for clicks on a
    /// divider. Returning false elsewhere means the event is delivered
    /// immediately (no double-click hold), so selecting a row never
    /// waits out the system double-click interval.
    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldAttemptToRecognizeWith event: NSEvent
    ) -> Bool {
        let point = splitView.convert(event.locationInWindow, from: nil)
        for dividerIndex in 0..<max(0, splitView.arrangedSubviews.count - 1)
        where dividerRect(at: dividerIndex).contains(point) {
            return true
        }
        return false
    }

    @objc private func handleDoubleClick(_ recogniser: NSClickGestureRecognizer) {
        let point = recogniser.location(in: splitView)
        for dividerIndex in 0..<max(0, splitView.arrangedSubviews.count - 1) {
            guard dividerRect(at: dividerIndex).contains(point) else { continue }
            let target = defaultTopHeight
            // `splitView.animator().setPosition` proxies the divider
            // move through Core Animation. Crucially we do NOT set
            // `allowsImplicitAnimation = true` — that would animate
            // every mutable property of every view inside, dragging
            // the SwiftUI-hosted content, NSOutlineView's selection
            // capsule, and the body pane's hairline divider along
            // for the ride and producing visual jitter.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                splitView.animator().setPosition(target, ofDividerAt: dividerIndex)
            }
            return
        }
    }

    /// Divider hit rect in `splitView` coordinates. We expand the
    /// drawn divider (often 1pt thin) by `hitPadding` on each side so
    /// the user has a realistic double-click target — `NSSplitView`'s
    /// own drag tracking does the same trick internally but doesn't
    /// expose the effective rect publicly. NSSplitView is flipped
    /// (origin at top), so for a horizontal-divider split the divider
    /// sits at the bottom edge of the indexed arranged subview.
    private func dividerRect(at index: Int) -> NSRect {
        guard index >= 0, index < splitView.arrangedSubviews.count - 1 else { return .zero }
        let subview = splitView.arrangedSubviews[index]
        let thickness = splitView.dividerThickness
        let hitPadding: CGFloat = 4
        if splitView.isVertical {
            return NSRect(
                x: subview.frame.maxX - hitPadding,
                y: 0,
                width: thickness + hitPadding * 2,
                height: splitView.bounds.height
            )
        } else {
            return NSRect(
                x: 0,
                y: subview.frame.maxY - hitPadding,
                width: splitView.bounds.width,
                height: thickness + hitPadding * 2
            )
        }
    }
}
