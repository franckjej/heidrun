import Foundation
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
