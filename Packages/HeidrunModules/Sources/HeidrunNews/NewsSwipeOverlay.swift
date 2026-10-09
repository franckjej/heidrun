import SwiftUI
import AppKit
import HeidrunUI
import CommonTools

/// Click-through layer over the threaded news panes: swipes, the mouse
/// side buttons and ⌘[ / ⌘] over them go back/forward, with the swipe
/// slide drawn from per-location page snapshots.
struct NewsSwipeOverlay: NSViewRepresentable {
    let viewModel: ThreadedNewsViewModel
    @Environment(\.heidrunContentSize) private var contentSize

    func makeNSView(context: Context) -> NewsSwipeOverlayView {
        let view = NewsSwipeOverlayView()
        view.wire(to: viewModel)
        return view
    }

    func updateNSView(_ view: NewsSwipeOverlayView, context: Context) {
        view.slideView.contentSize = contentSize
    }
}

final class NewsSwipeOverlayView: NSView {
    let slideView = SwipeSlideView()
    private let tracker = SwipeTracker()
    private var snapshots = SnapshotCache<NewsLocation, PageSnapshot>()
    private var eventMonitor: Any?
    private var goBack: () -> Void = {}
    private var goForward: () -> Void = {}

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        slideView.frame = bounds
        slideView.autoresizingMask = [.width, .height]
        addSubview(slideView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Clicks, drags and hovers reach the panes underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func wire(to viewModel: ThreadedNewsViewModel) {
        goBack = { [weak viewModel] in
            guard let viewModel else { return }
            Task { await viewModel.goBack() }
        }
        goForward = { [weak viewModel] in
            guard let viewModel else { return }
            Task { await viewModel.goForward() }
        }
        tracker.canGoBack = { [weak viewModel] in viewModel?.canGoBack ?? false }
        tracker.canGoForward = { [weak viewModel] in viewModel?.canGoForward ?? false }
        tracker.onBack = { [weak self] in self?.goBack() }
        tracker.onForward = { [weak self] in self?.goForward() }
        tracker.onSwipeBegan = { [weak self, weak viewModel] in
            self?.swipeBegan(back: viewModel?.backTarget, forward: viewModel?.forwardTarget)
        }
        tracker.onSwipeChanged = { [weak self] amount in self?.slideView.updateSlide(amount: amount) }
        tracker.onSwipeFinished = { [weak self] in self?.slideView.endSlide() }
        viewModel.onWillLeaveLocation = { [weak self] location in self?.rememberPage(for: location) }
    }

    // MARK: Events

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, eventMonitor == nil else { return }
        // The panes' own scroll views would swallow the swipe; a local
        // monitor sees it first, whichever pane is under the pointer.
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.scrollWheel, .swipe, .otherMouseDown, .keyDown]
        ) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        guard newWindow == nil, let eventMonitor else { return }
        NSEvent.removeMonitor(eventMonitor)
        self.eventMonitor = nil
    }

    /// Back/forward input over the panes; true when consumed.
    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window, !isHiddenOrHasHiddenAncestor else { return false }
        switch event.type {
        case .scrollWheel:
            return isUnderPointer(event) && tracker.track(event)
        case .swipe:
            guard isUnderPointer(event), event.deltaX != 0 else { return false }
            if event.deltaX > 0 {
                goBack()
            } else {
                goForward()
            }
            return true
        case .otherMouseDown:
            guard isUnderPointer(event) else { return false }
            switch event.buttonNumber {
            case 3:
                goBack()
                return true
            case 4:
                goForward()
                return true
            default:
                return false
            }
        case .keyDown:
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  hasKeyFocus(in: window)
            else { return false }
            switch event.charactersIgnoringModifiers {
            case "[":
                goBack()
                return true
            case "]":
                goForward()
                return true
            default:
                return false
            }
        default:
            return false
        }
    }

    private func isUnderPointer(_ event: NSEvent) -> Bool {
        bounds.contains(convert(event.locationInWindow, from: nil))
    }

    /// The focused view sits over the panes. The overlay isn't their
    /// ancestor, so compare window-space frames.
    private func hasKeyFocus(in window: NSWindow) -> Bool {
        guard window.isKeyWindow, let responder = window.firstResponder as? NSView else { return false }
        let focusFrame = responder.convert(responder.visibleRect, to: nil)
        return convert(bounds, to: nil).contains(NSPoint(x: focusFrame.midX, y: focusFrame.midY))
    }

    // MARK: Slide

    private func swipeBegan(back: NewsLocation?, forward: NewsLocation?) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        slideView.beginSlide(
            current: capturePage(),
            back: back.flatMap { snapshots.snapshot(for: $0) },
            forward: forward.flatMap { snapshots.snapshot(for: $0) }
        )
    }

    private func rememberPage(for location: NewsLocation) {
        snapshots.store(capturePage(), for: location)
    }

    /// The panes as drawn now, without the slide on top.
    private func capturePage() -> PageSnapshot? {
        guard let contentView = window?.contentView else { return nil }
        let wasHidden = slideView.isHidden
        slideView.isHidden = true
        defer { slideView.isHidden = wasHidden }
        return PageSnapshot.capture(
            of: contentView,
            rect: contentView.convert(bounds, from: self),
            contentSize: slideView.contentSize
        )
    }
}
