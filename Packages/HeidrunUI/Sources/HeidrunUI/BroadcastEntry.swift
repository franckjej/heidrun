import Foundation

/// One server broadcast (Hotline transID 355) queued for display.
///
/// `id` is a fresh UUID per instance so two identical messages in
/// quick succession enqueue as two distinct alerts instead of
/// coalescing — SwiftUI's `.alert(isPresented:presenting:)` re-
/// presents on identity change, so this matters.
public struct BroadcastEntry: Sendable, Identifiable, Hashable {
    public let id: UUID
    public let message: String
    public let receivedAt: Date

    public init(id: UUID = UUID(), message: String, receivedAt: Date = Date()) {
        self.id = id
        self.message = message
        self.receivedAt = receivedAt
    }
}
