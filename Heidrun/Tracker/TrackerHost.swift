import Foundation

/// One configured tracker host the user wants the tracker browser to
/// query. `id` is stable so the in-window editor's row identity
/// survives renames/re-orderings; the user-supplied `name` is what
/// shows up in the merged "Source" column when multiple trackers
/// report the same server.
struct TrackerHost: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var host: String
    var port: UInt16
    var enabled: Bool

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: UInt16 = 5498,
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.enabled = enabled
    }
}
