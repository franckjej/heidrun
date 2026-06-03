import Foundation
import HeidrunCore

/// Subscribes to a `HotlineClient`'s event stream and queues incoming
/// `.broadcastReceived` events for the host UI to surface as a modal.
///
/// Lifecycle mirrors `SoundCoordinator` / `UserListViewModel`: one
/// instance per `ConnectionHandle`, `start()` invoked once events are
/// flowing, `cancel()` on teardown. The `pending` FIFO outlives
/// individual alert presentations so multiple broadcasts arriving in a
/// burst stack and dismiss one at a time.
@MainActor
@Observable
public final class BroadcastViewModel {
    private let client: any HotlineClient
    private var listenTask: Task<Void, Never>?

    /// Queue of broadcasts the user hasn't dismissed yet. Head is what
    /// the UI currently presents (via `current`).
    public private(set) var pending: [BroadcastEntry] = []

    /// The broadcast currently displayed in the modal, or `nil` if the
    /// queue is empty.
    public var current: BroadcastEntry? { pending.first }

    public init(client: any HotlineClient) {
        self.client = client
    }

    /// Begin observing the client's event stream. Idempotent — calling
    /// twice cancels the previous loop first.
    public func start() async {
        listenTask?.cancel()
        let stream = client.events
        listenTask = Task { [weak self] in
            for await event in stream {
                if Task.isCancelled { break }
                self?.apply(event)
            }
        }
    }

    /// Tear down the observation loop. Pending entries are NOT cleared
    /// — the owning `ConnectionHandle` is about to deallocate the VM
    /// anyway, and dropping the queue here would risk losing the
    /// last alert in a clean-shutdown race.
    public func cancel() {
        listenTask?.cancel()
        listenTask = nil
    }

    /// Pop the head of the queue. Bound to the modal's dismiss action;
    /// SwiftUI re-renders on the next tick and the next entry (if any)
    /// auto-presents.
    public func dismissCurrent() {
        guard !pending.isEmpty else { return }
        pending.removeFirst()
    }

    private func apply(_ event: HotlineEvent) {
        guard case let .broadcastReceived(message) = event else { return }
        pending.append(BroadcastEntry(message: message))
    }
}
