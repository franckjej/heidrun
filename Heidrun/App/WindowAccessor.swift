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
        let view = NSView()
        // `window` is nil until the view joins a window. Defer until the
        // next runloop tick so the hierarchy has settled.
        DispatchQueue.main.async {
            onWindow(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Re-publish in case the view re-parents (rare on macOS but
        // possible during scene transitions).
        DispatchQueue.main.async {
            onWindow(nsView.window)
        }
    }
}
