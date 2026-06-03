import AppKit
import ObjectiveC

/// Keeps an `NSWindow.titlebarSeparatorStyle` pinned at `.none` despite
/// AppKit reinstalling the default `.automatic` value whenever the
/// toolbar is rebuilt.
///
/// A bare `window.titlebarSeparatorStyle = .none` is enough for static
/// toolbars, but SwiftUI's `.toolbar { ... }` re-installs the underlying
/// `NSToolbar` every time its content body re-evaluates — and for host
/// windows that happens whenever `HostToolbar` reads
/// `state.lastAttemptedSettings`, `activeTransferCount`, etc. AppKit
/// resets the separator style to `.automatic` during each reinstall,
/// which renders the hairline back.
///
/// The suppressor latches a single observer onto the window's
/// `didUpdateNotification` (AppKit fires this during each event-loop
/// update for the window) and re-applies `.none` cheaply. The observer
/// is associated with the window via an Objective-C runtime key so it
/// lives as long as the window does — no manual deinit needed and
/// `install(on:)` is idempotent across re-mounts.
@MainActor
enum ToolbarSeparatorSuppressor {
    /// Associated-object key — a static-storage byte's address is a
    /// stable per-process identity. `@MainActor`-isolated so Swift 6
    /// is satisfied (and AppKit work is on the main thread anyway).
    private static var keyByte: UInt8 = 0
    private static var keyPointer: UnsafeRawPointer {
        withUnsafePointer(to: &keyByte) { UnsafeRawPointer($0) }
    }

    static func install(on window: NSWindow) {
        // Idempotent: a window can mount > once if SwiftUI re-runs the
        // background modifier (which it does freely on every state
        // change). Subsequent calls are no-ops.
        if objc_getAssociatedObject(window, keyPointer) != nil { return }
        let observer = Observer(window: window)
        objc_setAssociatedObject(window, keyPointer, observer, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        // Apply once now so the first paint is clean — the observer
        // covers every subsequent rebuild.
        window.titlebarSeparatorStyle = .none
    }

    @MainActor
    private final class Observer: NSObject {
        weak var window: NSWindow?

        init(window: NSWindow) {
            self.window = window
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleUpdate(_:)),
                name: NSWindow.didUpdateNotification,
                object: window
            )
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc func handleUpdate(_ notification: Notification) {
            MainActor.assumeIsolated {
                guard let window = notification.object as? NSWindow else { return }
                if window.titlebarSeparatorStyle != .none {
                    window.titlebarSeparatorStyle = .none
                }
            }
        }
    }
}
