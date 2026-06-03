import Foundation
import Observation
import HeidrunCore

/// Drives the tracker browser UI. Queries every enabled `TrackerHost` in
/// parallel via `TrackerFetcher`, merges the per-tracker payloads by
/// `address:port`, and surfaces partial failures alongside successful
/// results.
///
/// Lifecycle: short-lived per surface (one VM per `TrackerWindow`,
/// another per `TrackerBrowser` sheet). The host list is injected at
/// construction time so the VM can be unit-tested without touching the
/// shared `TrackerHostsRegistry`. Production callers pass
/// `TrackerHostsRegistry.shared.hosts`.
@Observable
@MainActor
final class TrackerBrowserViewModel {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    /// Why a tracker fetch failed. `.timeout` (no response within the
    /// fetch deadline) is rendered red and counted in `timedOutCount`;
    /// everything else is `.other` (refused, bad host, malformed reply).
    enum FailureKind: Hashable {
        case timeout
        case other
    }

    struct FailedHost: Hashable {
        let host: TrackerHost
        let message: String
        let kind: FailureKind
    }

    var hosts: [TrackerHost]
    private(set) var servers: [MergedTrackerServer] = []
    private(set) var state: LoadState = .idle
    private(set) var failedHosts: [FailedHost] = []
    private let fetcher: any TrackerFetcher

    /// User-typed search filter. Case-insensitive substring across the
    /// server's `name`, `description`, and `address`. Whitespace-only
    /// values are treated as empty.
    var filter: String = ""

    /// Server list after applying `filter`. Sort comes from the SwiftUI
    /// `Table` directly via its `sortOrder` binding, so this property
    /// only filters.
    var filteredServers: [MergedTrackerServer] {
        let needle = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return servers }
        return servers.filter { row in
            row.server.name.lowercased().contains(needle)
                || row.server.description.lowercased().contains(needle)
                || row.server.address.lowercased().contains(needle)
        }
    }

    /// Number of enabled trackers that timed out on the last refresh.
    /// Drives the red "N timed out" badge next to the server count.
    var timedOutCount: Int {
        failedHosts.filter { $0.kind == .timeout }.count
    }

    init(
        hosts: [TrackerHost],
        fetcher: any TrackerFetcher = LiveTrackerFetcher()
    ) {
        self.hosts = hosts
        self.fetcher = fetcher
    }

    func refresh() async {
        // Snapshot so a user-initiated cancel can restore what was already
        // loaded instead of dropping it.
        let priorServers = servers
        let priorFailed = failedHosts

        state = .loading
        servers = []
        failedHosts = []

        let enabled = hosts.filter(\.enabled)
        if enabled.isEmpty {
            state = .loaded
            return
        }

        // Fan out via TaskGroup. Each child returns either the
        // tracker's server list or an error tagged with its host.
        let liveFetcher = fetcher
        let perHost: [(TrackerHost, Result<[TrackerServer], Error>)] = await withTaskGroup(
            of: (TrackerHost, Result<[TrackerServer], Error>).self,
            returning: [(TrackerHost, Result<[TrackerServer], Error>)].self
        ) { group in
            for host in enabled {
                group.addTask {
                    do {
                        let result = try await liveFetcher.fetchServers(host: host.host, port: host.port)
                        // Strip the empty separator rows the legacy
                        // tracker UI used to filter — keep the VM clean
                        // of "phantom" rows.
                        let cleaned = result.filter { !$0.name.isEmpty || !$0.description.isEmpty }
                        return (host, .success(cleaned))
                    } catch {
                        return (host, .failure(error))
                    }
                }
            }
            var collected: [(TrackerHost, Result<[TrackerServer], Error>)] = []
            for await pair in group { collected.append(pair) }
            return collected
        }

        // User cancelled mid-flight (Cancel button / window closed): keep
        // whatever was already loaded and don't mark unfinished trackers as
        // failures. The fetch's cancellation handler has already torn down
        // any in-flight connections.
        if Task.isCancelled {
            servers = priorServers
            failedHosts = priorFailed
            state = .loaded
            return
        }

        // Sort the per-host pairs back into stable host order so the
        // resulting merge is deterministic.
        let orderIndex: [TrackerHost.ID: Int] = Dictionary(
            uniqueKeysWithValues: enabled.enumerated().map { ($0.element.id, $0.offset) }
        )
        let ordered = perHost.sorted { lhs, rhs in
            (orderIndex[lhs.0.id] ?? .max) < (orderIndex[rhs.0.id] ?? .max)
        }

        var successReports: [(trackerName: String, servers: [TrackerServer])] = []
        var failures: [FailedHost] = []
        for (host, outcome) in ordered {
            switch outcome {
            case .success(let payload):
                successReports.append((host.name, payload))
            case .failure(let error):
                let didTimeOut = (error as? HotlineError) == .timedOut
                let message = didTimeOut
                    ? "No response (request timed out)"
                    : String(describing: error)
                failures.append(FailedHost(
                    host: host,
                    message: message,
                    kind: didTimeOut ? .timeout : .other
                ))
            }
        }

        servers = MergedTrackerServer.merge(reports: successReports)
        failedHosts = failures

        if successReports.isEmpty, !failures.isEmpty {
            // Surface the first failure verbatim — most callers will
            // also render the full `failedHosts` strip alongside.
            state = .failed(failures.first?.message ?? "unknown error")
        } else {
            state = .loaded
        }
    }
}
