import SwiftUI
import AppKit

extension View {
    /// Wire ⌘W to AppKit's close-window action on a window that
    /// otherwise doesn't have the chord bound (notably SwiftUI's
    /// `Settings` scene, which omits the standard "Close Window"
    /// File-menu item that carries the shortcut on document and
    /// `WindowGroup` windows).
    ///
    /// Implementation: a zero-sized hidden button in the background
    /// owns `.keyboardShortcut("w", modifiers: .command)` and routes
    /// the chord to `NSApp.keyWindow?.performClose(nil)` — the same
    /// action a click on the red traffic-light dot performs.
    func commandWCloseShortcut() -> some View {
        background {
            Button("", action: { NSApp.keyWindow?.performClose(nil) })
                .keyboardShortcut("w", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}
