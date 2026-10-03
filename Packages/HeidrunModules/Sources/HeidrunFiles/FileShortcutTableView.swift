import AppKit

/// NSTableView adding the list's shortcuts: Cmd+I → Get Info, Space →
/// Quick Look, Cmd+[ / Cmd+] / Cmd+↑ → back / forward / up. Also turns
/// horizontal trackpad swipes and the mouse side buttons into
/// back/forward. Anything else falls through to NSTableView.
final class FileShortcutTableView: NSTableView {
    var onCommandI: () -> Void = {}
    var onSpace: () -> Void = {}
    var onBack: () -> Void = {}
    var onForward: () -> Void = {}
    var onUp: () -> Void = {}
    var canGoBack: () -> Bool = { false }
    var canGoForward: () -> Bool = { false }
    /// Slide hooks: began, continuous amount (> 0 back, < 0 forward), done.
    var onSwipeBegan: () -> Void = {}
    var onSwipeChanged: (CGFloat) -> Void = { _ in }
    var onSwipeFinished: () -> Void = {}
    /// Bumped per two-finger swipe; only the newest one drives the slide.
    private var swipeSerial = 0

    override func keyDown(with event: NSEvent) {
        let chars = event.charactersIgnoringModifiers ?? ""
        if event.modifierFlags.contains(.command) {
            if event.specialKey == .upArrow {
                onUp()
                return
            }
            switch chars {
            case "i":
                onCommandI()
                return
            case "[":
                onBack()
                return
            case "]":
                onForward()
                return
            default:
                break
            }
        }
        if chars == " " {
            onSpace()
            return
        }
        super.keyDown(with: event)
    }

    /// Two-finger horizontal swipe ("Swipe between pages"): fingers right
    /// = back, left = forward, like Safari.
    override func scrollWheel(with event: NSEvent) {
        let canBack = canGoBack()
        let canForward = canGoForward()
        guard event.phase == .began,
              NSEvent.isSwipeTrackingFromScrollEventsEnabled,
              abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
              canBack || canForward
        else {
            super.scrollWheel(with: event)
            return
        }
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
            self.onSwipeChanged(gestureAmount)
            // Past the threshold: navigate now so the cached listing is in
            // place by the time the slide finishes.
            if phase == .ended {
                if gestureAmount > 0 {
                    self.onBack()
                } else if gestureAmount < 0 {
                    self.onForward()
                }
            }
            if isComplete {
                self.onSwipeFinished()
            }
        }
    }

    /// Three-finger swipe (when the trackpad is set to it).
    override func swipe(with event: NSEvent) {
        if event.deltaX > 0 {
            onBack()
        } else if event.deltaX < 0 {
            onForward()
        } else {
            super.swipe(with: event)
        }
    }

    /// Mouse side buttons: 3 = back, 4 = forward.
    override func otherMouseDown(with event: NSEvent) {
        switch event.buttonNumber {
        case 3:
            onBack()
        case 4:
            onForward()
        default:
            super.otherMouseDown(with: event)
        }
    }
}
