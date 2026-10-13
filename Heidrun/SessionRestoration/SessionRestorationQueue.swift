import AppKit
import HeidrunCore

/// In-memory queue of connections each freshly-mounted `RootView` pumps
/// at launch. Seeded once from `SessionRestorationStore` in
/// `HeidrunMainApp.init()`; each mounting window dequeues one, connects,
/// and opens another host window when entries remain.
///
/// Launch-only since the DocumentGroup migration — run-time spawns
/// (Bookmarks menu, Recent Servers, URL launches) go through
/// `\.openDocument` or `\.newDocument { .seeded(with:) }` instead.
@MainActor
final class SessionRestorationQueue {
    static let shared = SessionRestorationQueue()

    private var pending: [ConnectionSettings] = []

    var isEmpty: Bool { pending.isEmpty }

    var count: Int { pending.count }

    /// Called once per launch — overwrites any pending entries.
    func populate(_ settings: [ConnectionSettings]) {
        pending = settings
    }

    func enqueue(_ settings: ConnectionSettings) {
        pending.append(settings)
    }

    /// First restored window; later restore windows tab into its group.
    private weak var anchorWindow: NSWindow?

    /// AppKit only auto-tabs a new window into the key window's group, and
    /// there's no key window while Touch ID unlocks a saved password — so
    /// restores came up as separate windows. Tab them explicitly, honouring
    /// the system "Prefer tabs" setting.
    func joinRestoreTabGroup(_ window: NSWindow) {
        guard let anchorWindow, anchorWindow !== window else {
            anchorWindow = window
            return
        }
        let prefersTabs = switch NSWindow.userTabbingPreference {
        case .always:
            true
        case .inFullScreen:
            anchorWindow.styleMask.contains(.fullScreen)
        default:
            false
        }
        guard prefersTabs, anchorWindow.tabbedWindows?.contains(window) != true else { return }
        anchorWindow.addTabbedWindow(window, ordered: .above)
    }

    func dequeue() -> ConnectionSettings? {
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }

    /// `RootView` reads this at body-time so a freshly-mounted window
    /// renders `ConnectingPane` on its FIRST frame instead of flashing
    /// `ConnectionForm` before `.task` can fire `dequeue()`.
    func peek() -> ConnectionSettings? {
        pending.first
    }
}
