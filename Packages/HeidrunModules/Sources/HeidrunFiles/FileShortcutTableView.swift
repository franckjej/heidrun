import AppKit
import HeidrunUI

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
    /// Two-finger swipe → back/forward + slide; set up by the owner.
    let swipeTracker = SwipeTracker()

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

    /// Two-finger horizontal swipe ("Swipe between pages").
    override func scrollWheel(with event: NSEvent) {
        if !swipeTracker.track(event) {
            super.scrollWheel(with: event)
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
