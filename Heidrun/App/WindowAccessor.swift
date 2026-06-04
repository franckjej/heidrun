import SwiftUI
import AppKit

/// Reaches up to the SwiftUI-hosted view's owning `NSWindow` and hands
/// it back to a caller. Use it as `.background(WindowAccessor { ... })`
/// to capture the window once it's mounted — needed when something
/// external (e.g. the TaskManager) wants to bring a specific window
/// forward without going through `WindowGroup`'s opaque id system.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = WindowCaptureView()
        view.onWindow = onWindow
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-publish on body updates so phase-driven title/style changes
        // re-stamp the window. Sync — no DispatchQueue hop. By the
        // time `updateNSView` runs the view is already in the window.
        onWindow(nsView.window)
    }
}

/// Fires the consumer's callback the instant `viewDidMoveToWindow` lands
/// (synchronously, before the next paint) rather than deferring to the
/// next run-loop tick. The deferral is what produced a one-frame flash
/// of the DocumentGroup-auto-set title and default toolbar style before
/// the consumer's overrides applied.
private final class WindowCaptureView: NSView {
    var onWindow: ((NSWindow?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindow?(window)
    }
}
