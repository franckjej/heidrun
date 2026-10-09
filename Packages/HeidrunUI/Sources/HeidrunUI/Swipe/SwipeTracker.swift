import AppKit

/// Two-finger horizontal swipe ("Swipe between pages") → back/forward:
/// fingers right = back, left = forward, like Safari.
@MainActor
public final class SwipeTracker {
    public var canGoBack: () -> Bool = { false }
    public var canGoForward: () -> Bool = { false }
    public var onBack: () -> Void = {}
    public var onForward: () -> Void = {}
    /// Slide hooks: began, continuous amount (> 0 back, < 0 forward), done.
    public var onSwipeBegan: () -> Void = {}
    public var onSwipeChanged: (CGFloat) -> Void = { _ in }
    public var onSwipeFinished: () -> Void = {}
    /// Bumped per swipe; only the newest one drives the slide.
    private var swipeSerial = 0

    public init() {}

    /// Tracks `event` when it starts a horizontal swipe with somewhere to
    /// go; false (event untouched) otherwise.
    public func track(_ event: NSEvent) -> Bool {
        let canBack = canGoBack()
        let canForward = canGoForward()
        guard event.phase == .began,
              NSEvent.isSwipeTrackingFromScrollEventsEnabled,
              abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
              canBack || canForward
        else { return false }
        swipeSerial += 1
        let serial = swipeSerial
        onSwipeBegan()
        event.trackSwipeEvent(
            options: [.lockDirection, .clampGestureAmount],
            dampenAmountThresholdMin: canForward ? -1 : 0,
            max: canBack ? 1 : 0
        ) { [weak self] gestureAmount, phase, isComplete, stop in
            guard let self else { return }
            // A newer swipe started while this one was still settling:
            // AppKit keeps calling both, so drop the old one.
            guard serial == self.swipeSerial else {
                stop.pointee = true
                return
            }
            // No target that way: hold still instead of rubber-banding a
            // blank page in.
            let amount = min(max(gestureAmount, canForward ? -1 : 0), canBack ? 1 : 0)
            self.onSwipeChanged(amount)
            // Past the threshold: navigate now so the cached page is in
            // place by the time the slide finishes.
            if phase == .ended {
                if amount > 0 {
                    self.onBack()
                } else if amount < 0 {
                    self.onForward()
                }
            }
            if isComplete {
                self.onSwipeFinished()
            }
        }
        return true
    }
}
