import Foundation
import HeidrunCore

/// UI-level wrapper around `TrackerServer` that aggregates multiple
/// tracker reports for the same `address:port` into a single row.
/// `sources` is the list of tracker `name`s that reported this server,
/// rendered in the "Source" table column when 2+ trackers are
/// configured.
struct MergedTrackerServer: Identifiable, Hashable, Sendable {
    let server: TrackerServer
    var sources: [String]

    /// Stable id derived from the network identity. Using a plain
    /// String (not the synthesised Hashable id) avoids `Int.description`
    /// going through the user's locale grouping separator, which would
    /// emit e.g. "10.0.0.1:5.500" on a `de_DE` system.
    var id: String { "\(server.address):\(server.port)" }

    /// Fold per-tracker server reports into a deduplicated list keyed by
    /// `address:port`. When the same server is reported by N trackers,
    /// the row's `users` count comes from whichever tracker reported the
    /// highest number (closest proxy to "freshest reading" since
    /// trackers don't carry timestamps).
    ///
    /// `reports` is `(trackerName, [TrackerServer])` so the source name
    /// rides alongside each tracker's payload.
    static func merge(
        reports: [(trackerName: String, servers: [TrackerServer])]
    ) -> [MergedTrackerServer] {
        var byID: [String: MergedTrackerServer] = [:]
        var order: [String] = []
        for (trackerName, servers) in reports {
            for server in servers {
                let key = "\(server.address):\(server.port)"
                if var existing = byID[key] {
                    if server.users > existing.server.users {
                        existing = MergedTrackerServer(
                            server: server,
                            sources: existing.sources
                        )
                    }
                    if !existing.sources.contains(trackerName) {
                        existing.sources.append(trackerName)
                    }
                    byID[key] = existing
                } else {
                    byID[key] = MergedTrackerServer(server: server, sources: [trackerName])
                    order.append(key)
                }
            }
        }
        return order.compactMap { byID[$0] }
    }
}
