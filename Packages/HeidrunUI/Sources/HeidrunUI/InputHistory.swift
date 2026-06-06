import Foundation

/// Shell-style history of sent input lines, with ↑/↓ recall.
///
/// Holds the messages a user has sent (oldest → newest, capped), plus the
/// transient navigation state the input field drives: a cursor into the
/// list and the live draft stashed when navigation begins, so paging back
/// down past the newest entry restores whatever the user was typing.
///
/// Value type — owned by a view model so the history survives module
/// switches but stays in memory only (no persistence). Reusable across
/// any text input; the chat module wires it first.
public struct InputHistory: Sendable {
    private var entries: [String] = []      // oldest → newest
    private var cursor: Int?                 // nil = not navigating
    private var stashedDraft: String = ""    // live draft saved when nav begins
    private let capacity: Int

    public init(capacity: Int = 50) {
        self.capacity = max(1, capacity)
    }

    /// Sent messages, newest first — suitable for a "recent" menu.
    public var recent: [String] { entries.reversed() }

    /// Record a freshly sent message. Empty / whitespace-only messages and
    /// consecutive duplicates are skipped. Always resets navigation so the
    /// next ↑ starts from the newest entry.
    public mutating func record(_ message: String) {
        defer { resetNavigation() }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, entries.last != trimmed else { return }
        entries.append(trimmed)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    /// Abandon any in-progress ↑/↓ navigation.
    public mutating func resetNavigation() {
        cursor = nil
    }

    /// Step to an older entry (↑). The first call stashes `currentDraft`
    /// so it can be restored by paging back down. Returns the recalled
    /// text, or `nil` when already at the oldest entry / history is empty
    /// (caller leaves the field unchanged).
    public mutating func recallPrevious(currentDraft: String) -> String? {
        guard !entries.isEmpty else { return nil }
        switch cursor {
        case nil:
            stashedDraft = currentDraft
            cursor = entries.count - 1
        case let index? where index > 0:
            cursor = index - 1
        default:
            return nil   // already at the oldest
        }
        return entries[cursor!]
    }

    /// Step to a newer entry (↓). Past the newest entry it restores the
    /// stashed live draft and ends navigation. Returns `nil` when not
    /// currently navigating (caller leaves the field unchanged).
    public mutating func recallNext() -> String? {
        guard let index = cursor else { return nil }
        if index < entries.count - 1 {
            cursor = index + 1
            return entries[cursor!]
        }
        cursor = nil
        return stashedDraft
    }
}
