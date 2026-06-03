import Foundation
import Testing
@testable import HeidrunNews
import HeidrunCore

@Suite("NewsClipboardFormatter")
struct NewsClipboardFormatterTests {
    /// Stable date — 2026-05-24 14:32 UTC. Built via `DateComponents`
    /// so the value is unambiguous (avoids magic-number drift between
    /// the comment and the underlying epoch seconds).
    private static let fixedDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 5
        components.day = 24
        components.hour = 14
        components.minute = 32
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    @Test("formatPost emits Subject / From / Date header, blank line, then body")
    func formatPost_singleElement_emitsHeaderAndBody() {
        let thread = NewsThread(
            threadID: 1,
            parentID: 0,
            postDate: Self.fixedDate,
            elements: [
                ThreadElement(
                    title: "Server downtime",
                    author: "admin",
                    body: "Going down in 5 min."
                )
            ]
        )
        let expected = """
        Subject: Server downtime
        From: admin
        Date: 2026-05-24 14:32

        Going down in 5 min.
        """
        #expect(NewsClipboardFormatter.formatPost(thread) == expected)
    }

    @Test("formatPost emits (unknown) when author is missing")
    func formatPost_missingAuthor_emitsUnknown() {
        let thread = NewsThread(
            threadID: 1,
            postDate: Self.fixedDate,
            elements: [ThreadElement(title: "x", author: "", body: "y")]
        )
        let rendered = NewsClipboardFormatter.formatPost(thread)
        #expect(rendered.contains("From: (unknown)"))
    }

    @Test("formatPost emits (untitled) when title is missing")
    func formatPost_missingTitle_emitsUntitled() {
        let thread = NewsThread(
            threadID: 1,
            postDate: Self.fixedDate,
            elements: [ThreadElement(title: "", author: "a", body: "y")]
        )
        let rendered = NewsClipboardFormatter.formatPost(thread)
        #expect(rendered.contains("Subject: (untitled)"))
    }

    @Test("formatPost date format is locale-independent (yyyy-MM-dd HH:mm)")
    func formatPost_dateIsLocaleIndependent() {
        let thread = NewsThread(
            threadID: 1,
            postDate: Self.fixedDate,
            elements: [ThreadElement(title: "t", author: "a", body: "")]
        )
        let rendered = NewsClipboardFormatter.formatPost(thread)
        #expect(rendered.contains("Date: 2026-05-24 14:32"))
    }

    @Test("formatPost keeps header + blank-line shape when body is empty")
    func formatPost_emptyBody_keepsHeaderShape() {
        let thread = NewsThread(
            threadID: 1,
            postDate: Self.fixedDate,
            elements: [ThreadElement(title: "t", author: "a", body: "")]
        )
        let rendered = NewsClipboardFormatter.formatPost(thread)
        // 4 lines + trailing newline before body = ends with "\n\n"
        // (Subject\nFrom\nDate\n\n + empty body)
        #expect(rendered.hasSuffix("\n\n"))
    }

    @Test("formatThread on a single node matches formatPost")
    func formatThread_singleNode_matchesFormatPost() {
        let thread = NewsThread(
            threadID: 1,
            postDate: Self.fixedDate,
            elements: [ThreadElement(title: "t", author: "a", body: "b")]
        )
        let viaPost = NewsClipboardFormatter.formatPost(thread)
        let viaTree = NewsClipboardFormatter.formatThread(thread, descendantsFrom: [thread])
        #expect(viaPost == viaTree)
    }

    @Test("formatThread joins parent + reply with the --- separator")
    func formatThread_parentWithReply_joinedBySeparator() {
        let parent = NewsThread(
            threadID: 1,
            parentID: 0,
            postDate: Self.fixedDate,
            elements: [ThreadElement(title: "Parent", author: "a", body: "one")]
        )
        let reply = NewsThread(
            threadID: 2,
            parentID: 1,
            postDate: Self.fixedDate.addingTimeInterval(60),
            elements: [ThreadElement(title: "Reply", author: "b", body: "two")]
        )
        let rendered = NewsClipboardFormatter.formatThread(parent, descendantsFrom: [parent, reply])
        #expect(rendered.contains("Subject: Parent"))
        #expect(rendered.contains("Subject: Reply"))
        #expect(rendered.contains("\n---\n"))
    }

    @Test("formatThread orders descendants depth-first by postDate ascending")
    func formatThread_depthFirstByDate() {
        // Tree:
        //   root (date 100)
        //   ├── childA (date 200)
        //   │   └── grandchild (date 300)
        //   └── childB (date 400)
        let root = NewsThread(
            threadID: 1,
            parentID: 0,
            postDate: Date(timeIntervalSince1970: 100),
            elements: [ThreadElement(title: "Root", author: "a", body: "")]
        )
        let childA = NewsThread(
            threadID: 2,
            parentID: 1,
            postDate: Date(timeIntervalSince1970: 200),
            elements: [ThreadElement(title: "ChildA", author: "a", body: "")]
        )
        let grandchild = NewsThread(
            threadID: 3,
            parentID: 2,
            postDate: Date(timeIntervalSince1970: 300),
            elements: [ThreadElement(title: "Grandchild", author: "a", body: "")]
        )
        let childB = NewsThread(
            threadID: 4,
            parentID: 1,
            postDate: Date(timeIntervalSince1970: 400),
            elements: [ThreadElement(title: "ChildB", author: "a", body: "")]
        )
        let rendered = NewsClipboardFormatter.formatThread(root, descendantsFrom: [root, childA, grandchild, childB])
        // Verify positions: Root before ChildA before Grandchild before ChildB.
        let rootIdx = rendered.range(of: "Subject: Root")?.lowerBound
        let childAIdx = rendered.range(of: "Subject: ChildA")?.lowerBound
        let grandchildIdx = rendered.range(of: "Subject: Grandchild")?.lowerBound
        let childBIdx = rendered.range(of: "Subject: ChildB")?.lowerBound
        let unwrapped = [rootIdx, childAIdx, grandchildIdx, childBIdx].compactMap { $0 }
        #expect(unwrapped.count == 4)
        #expect(unwrapped == unwrapped.sorted())
    }

    @Test("formatThreadList of a single root equals formatThread")
    func formatThreadList_singleRoot_matchesFormatThread() {
        let root = NewsThread(
            threadID: 1,
            parentID: 0,
            postDate: Self.fixedDate,
            elements: [ThreadElement(title: "Only", author: "a", body: "x")]
        )
        let viaList = NewsClipboardFormatter.formatThreadList([root])
        let viaThread = NewsClipboardFormatter.formatThread(root, descendantsFrom: [root])
        #expect(viaList == viaThread)
    }

    @Test("formatThreadList orders roots by postDate and joins with ---")
    func formatThreadList_multipleRoots_sortedJoined() {
        let early = NewsThread(
            threadID: 1,
            parentID: 0,
            postDate: Date(timeIntervalSince1970: 100),
            elements: [ThreadElement(title: "Early", author: "a", body: "1")]
        )
        let late = NewsThread(
            threadID: 2,
            parentID: 0,
            postDate: Date(timeIntervalSince1970: 200),
            elements: [ThreadElement(title: "Late", author: "b", body: "2")]
        )
        // Supplied out of order to prove the formatter sorts.
        let rendered = NewsClipboardFormatter.formatThreadList([late, early])
        let earlyIdx = rendered.range(of: "Subject: Early")?.lowerBound
        let lateIdx = rendered.range(of: "Subject: Late")?.lowerBound
        #expect(earlyIdx != nil && lateIdx != nil)
        #expect(earlyIdx! < lateIdx!)
        #expect(rendered.contains("\n---\n"))
    }

    @Test("formatThreadList treats an orphan reply as a root")
    func formatThreadList_orphanReply_isRoot() {
        let root = NewsThread(
            threadID: 1,
            parentID: 0,
            postDate: Date(timeIntervalSince1970: 100),
            elements: [ThreadElement(title: "Root", author: "a", body: "")]
        )
        // parentID 99 is not a threadID present in the list → orphan → root.
        let orphan = NewsThread(
            threadID: 2,
            parentID: 99,
            postDate: Date(timeIntervalSince1970: 200),
            elements: [ThreadElement(title: "Orphan", author: "b", body: "")]
        )
        let rendered = NewsClipboardFormatter.formatThreadList([root, orphan])
        #expect(rendered.contains("Subject: Root"))
        #expect(rendered.contains("Subject: Orphan"))
    }

    @Test("formatThreadList of an empty list is the empty string")
    func formatThreadList_empty_returnsEmpty() {
        #expect(NewsClipboardFormatter.formatThreadList([]).isEmpty)
    }

    @Test("formatBundleContents emits a ## header per section, joined by blank lines")
    func formatBundleContents_headersAndSeparators() {
        let alpha = NewsThread(
            threadID: 1,
            parentID: 0,
            postDate: Self.fixedDate,
            elements: [ThreadElement(title: "A1", author: "a", body: "one")]
        )
        let beta = NewsThread(
            threadID: 2,
            parentID: 0,
            postDate: Self.fixedDate,
            elements: [ThreadElement(title: "B1", author: "b", body: "two")]
        )
        let rendered = NewsClipboardFormatter.formatBundleContents(
            sections: [
                (heading: "Alpha", threads: [alpha]),
                (heading: "Beta", threads: [beta])
            ]
        )
        #expect(rendered.contains("## Alpha"))
        #expect(rendered.contains("## Beta"))
        #expect(rendered.contains("Subject: A1"))
        #expect(rendered.contains("Subject: B1"))
        let alphaIdx = rendered.range(of: "## Alpha")?.lowerBound
        let betaIdx = rendered.range(of: "## Beta")?.lowerBound
        #expect(alphaIdx! < betaIdx!)
    }

    @Test("formatBundleContents still emits the header for an empty category")
    func formatBundleContents_emptyCategory_stillEmitsHeader() {
        let rendered = NewsClipboardFormatter.formatBundleContents(
            sections: [(heading: "Empty", threads: [])]
        )
        #expect(rendered == "## Empty\n\n")
    }
}
