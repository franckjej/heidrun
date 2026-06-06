import Foundation
import Observation
import HeidrunCore

/// View-model behind the legacy "plain news" feed.
///
/// Hotline's plain news is a single appended-to text blob that every server
/// supports. New posts arrive as `HotlineEvent.newsPosted`; the original
/// store on the server is fetched once via `fetchNewsFeed()`.
@Observable
@MainActor
public final class PlainNewsViewModel {
    /// Whole feed text in display order (newest at the top, like the
    /// original Heidrun UI prepended).
    public private(set) var feed: String = ""

    /// Two-way bound input field for a new post.
    public var draft: String = ""

    public private(set) var isLoading: Bool = false

    private let events: AsyncStream<HotlineEvent>
    private let fetchFeed: @Sendable () async throws -> String
    private let postNew: @Sendable (String) async throws -> Void
    private let present: @MainActor (Error) -> Void

    /// Task wrapping `observe()` when the VM is owned by a long-lived
    /// host (`ConnectionHandle`) rather than a transient view `.task`.
    /// Keeping the loop at connection scope means a `.newsPosted` push
    /// lands on the feed even when the user is looking at another module
    /// — and survives switching away from News and back, which would
    /// otherwise tear down a view-scoped observation and never restore
    /// it (the captured stream is single-shot).
    private var observationTask: Task<Void, Never>?

    public init(
        events: AsyncStream<HotlineEvent>,
        fetchFeed: @escaping @Sendable () async throws -> String,
        postNew: @escaping @Sendable (String) async throws -> Void,
        present: @escaping @MainActor (Error) -> Void = { _ in }
    ) {
        self.events = events
        self.fetchFeed = fetchFeed
        self.postNew = postNew
        self.present = present
    }

    public convenience init(
        client: any HotlineClient,
        present: @escaping @MainActor (Error) -> Void = { _ in }
    ) {
        self.init(
            events: client.events,
            fetchFeed: { [client] in try await client.fetchNewsFeed() },
            postNew: { [client] text in try await client.postPlainNews(text) },
            present: present
        )
    }

    public func observe() async {
        for await event in events {
            if case let .newsPosted(text) = event {
                feed = text + "\n\n" + feed
            }
        }
    }

    /// Start `observe()` in a managed Task. Use this when the VM is
    /// owned by something longer-lived than the News view, so live posts
    /// keep arriving across module switches. Idempotent — calling twice
    /// (e.g. once from `ConnectionHandle` and again when the News tab
    /// first appears) does nothing.
    public func start() {
        guard observationTask == nil else { return }
        observationTask = Task { [weak self] in
            await self?.observe()
        }
    }

    /// Stop the observation task started by `start()`. Safe to call
    /// when no task is running.
    public func cancel() {
        observationTask?.cancel()
        observationTask = nil
    }

    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            feed = try await fetchFeed()
        } catch {
            present(error)
        }
    }

    /// Post the current draft. Whitespace-only drafts are a no-op so an
    /// accidental Return doesn't post an empty banner.
    public func postDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            try await postNew(text)
            draft = ""
        } catch {
            present(error)
        }
    }
}
