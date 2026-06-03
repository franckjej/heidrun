import Foundation
import HeidrunCore

/// Pure plain-text formatter that turns a `NewsThread` (or a thread +
/// its descendants) into clipboard-ready text. No AppKit, no actor
/// isolation — safe to call from anywhere.
///
/// Output shape, single post:
///
/// ```
/// Subject: <title>
/// From: <author>
/// Date: <yyyy-MM-dd HH:mm>
///
/// <body>
/// ```
///
/// Output shape, tree: same per-post format, depth-first by `postDate`
/// ascending at each level, joined by `\n---\n` between adjacent posts.
public enum NewsClipboardFormatter {

    public static func formatPost(_ thread: NewsThread) -> String {
        let element = thread.elements.first
        let subject = element?.title.nonEmptyText ?? "(untitled)"
        let from = element?.author.nonEmptyText ?? "(unknown)"
        let date = Self.dateFormatter.string(from: thread.postDate)
        let body = element?.body ?? ""
        return """
        Subject: \(subject)
        From: \(from)
        Date: \(date)

        \(body)
        """
    }

    public static func formatThread(
        _ thread: NewsThread,
        descendantsFrom allThreads: [NewsThread]
    ) -> String {
        let ordered = depthFirst(rootID: thread.threadID, all: allThreads)
        return ordered.map(formatPost).joined(separator: "\n---\n")
    }

    /// Render every thread in a flat category list. A *root* is any
    /// thread whose `parentID` is not the `threadID` of another thread in
    /// the list — this captures genuine top-level posts (`parentID == 0`)
    /// and orphans left by an edit (delete-no-cascade then repost). Roots
    /// are sorted by `postDate`; each root's subtree is rendered by
    /// `formatThread`, and roots are joined by the same `\n---\n`
    /// separator so the category reads as one uniform stream.
    public static func formatThreadList(_ threads: [NewsThread]) -> String {
        let knownIDs = Set(threads.map(\.threadID))
        let roots = threads
            .filter { thread in !knownIDs.contains(thread.parentID) }
            .sorted { lhs, rhs in lhs.postDate < rhs.postDate }
        return roots
            .map { root in formatThread(root, descendantsFrom: threads) }
            .joined(separator: "\n---\n")
    }

    /// Render a folder's gathered sections. Each section is one category's
    /// heading plus its `formatThreadList` body; sections are joined by a
    /// blank line. A two-element labeled tuple (not a three-element one)
    /// keeps `large_tuple` quiet while staying lighter than a named type.
    public static func formatBundleContents(
        sections: [(heading: String, threads: [NewsThread])]
    ) -> String {
        sections
            .map { section in "## \(section.heading)\n\n\(formatThreadList(section.threads))" }
            .joined(separator: "\n\n")
    }

    // MARK: - Internals

    /// Locale-independent format so pasted text is stable across
    /// machines and locales. Constructed once and held.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// Depth-first traversal rooted at `rootID`, ordering siblings by
    /// `postDate` ascending. Threads without `rootID` as an ancestor
    /// are dropped silently.
    private static func depthFirst(
        rootID: UInt16,
        all allThreads: [NewsThread]
    ) -> [NewsThread] {
        var byParent: [UInt16: [NewsThread]] = [:]
        var byID: [UInt16: NewsThread] = [:]
        for thread in allThreads {
            byParent[thread.parentID, default: []].append(thread)
            byID[thread.threadID] = thread
        }
        for parentID in byParent.keys {
            byParent[parentID]?.sort { $0.postDate < $1.postDate }
        }
        guard let root = byID[rootID] else { return [] }
        var ordered: [NewsThread] = []
        var stack: [NewsThread] = [root]
        while let next = stack.popLast() {
            ordered.append(next)
            let children = byParent[next.threadID] ?? []
            // Push reversed so we pop in ascending date order.
            stack.append(contentsOf: children.reversed())
        }
        return ordered
    }
}

private extension String {
    /// `nil` when this string is empty, otherwise itself. Local to
    /// the formatter so it doesn't collide with the same-named helper
    /// `private extension String { nonEmpty }` in `NewsView.swift`.
    var nonEmptyText: String? { isEmpty ? nil : self }
}
