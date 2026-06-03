import Foundation
import os
import Testing
@testable import Heidrun
import HeidrunCore

@MainActor
@Suite("TrackerBrowserViewModel")
struct TrackerBrowserViewModelTests {
    @Test("idle until refresh; servers empty")
    func startsIdle() {
        let fetcher = RecordingFetcher()
        let viewModel = TrackerBrowserViewModel(
            hosts: [],
            fetcher: fetcher
        )
        #expect(viewModel.state == .idle)
        #expect(viewModel.servers.isEmpty)
        #expect(viewModel.failedHosts.isEmpty)
    }

    @Test("refresh with no enabled hosts → loaded + empty")
    func refreshWithNoHosts() async {
        let fetcher = RecordingFetcher()
        let viewModel = TrackerBrowserViewModel(
            hosts: [],
            fetcher: fetcher
        )
        await viewModel.refresh()
        #expect(viewModel.state == .loaded)
        #expect(viewModel.servers.isEmpty)
        #expect(fetcher.callCount == 0)
    }

    @Test("refresh fans out to every enabled host")
    func refreshFansOut() async {
        let fetcher = RecordingFetcher()
        fetcher.responses["a.example"] = .success([
            TrackerServer(address: "1.1.1.1", port: 5500, users: 1, name: "one", description: "")
        ])
        fetcher.responses["b.example"] = .success([
            TrackerServer(address: "2.2.2.2", port: 5500, users: 2, name: "two", description: "")
        ])
        let viewModel = TrackerBrowserViewModel(
            hosts: [
                TrackerHost(name: "a", host: "a.example", port: 5498),
                TrackerHost(name: "b", host: "b.example", port: 5498),
                TrackerHost(name: "off", host: "off.example", port: 5498, enabled: false)
            ],
            fetcher: fetcher
        )
        await viewModel.refresh()
        #expect(viewModel.state == .loaded)
        #expect(viewModel.servers.count == 2)
        #expect(Set(viewModel.servers.map(\.id)) == Set(["1.1.1.1:5500", "2.2.2.2:5500"]))
        #expect(Set(fetcher.invokedHosts) == Set(["a.example", "b.example"]))
        // Disabled host must NOT be queried.
        #expect(fetcher.invokedHosts.contains("off.example") == false)
    }

    @Test("partial failure surfaces failed hosts + keeps successful results")
    func partialFailure() async {
        struct Boom: Error {}
        let fetcher = RecordingFetcher()
        fetcher.responses["good.example"] = .success([
            TrackerServer(address: "1.1.1.1", port: 5500, users: 1, name: "g", description: "")
        ])
        fetcher.responses["bad.example"] = .failure(Boom())
        let viewModel = TrackerBrowserViewModel(
            hosts: [
                TrackerHost(name: "good", host: "good.example"),
                TrackerHost(name: "bad", host: "bad.example")
            ],
            fetcher: fetcher
        )
        await viewModel.refresh()
        #expect(viewModel.state == .loaded)
        #expect(viewModel.servers.count == 1)
        #expect(viewModel.failedHosts.count == 1)
        #expect(viewModel.failedHosts.first?.host.host == "bad.example")
    }

    @Test("all-failure → failed state")
    func allFailure() async {
        struct Boom: Error {}
        let fetcher = RecordingFetcher()
        fetcher.responses["bad.example"] = .failure(Boom())
        let viewModel = TrackerBrowserViewModel(
            hosts: [TrackerHost(name: "bad", host: "bad.example")],
            fetcher: fetcher
        )
        await viewModel.refresh()
        if case .failed = viewModel.state {
            // ok
        } else {
            Issue.record("expected .failed, got \(viewModel.state)")
        }
        #expect(viewModel.servers.isEmpty)
        #expect(viewModel.failedHosts.count == 1)
    }

    @Test("timed-out host is classified .timeout, counted, and does not sink successes")
    func timeoutClassifiedAndCounted() async {
        let fetcher = RecordingFetcher()
        fetcher.responses["good.example"] = .success([
            TrackerServer(address: "1.1.1.1", port: 5500, users: 1, name: "g", description: "")
        ])
        fetcher.responses["slow.example"] = .failure(HotlineError.timedOut)
        let viewModel = TrackerBrowserViewModel(
            hosts: [
                TrackerHost(name: "good", host: "good.example"),
                TrackerHost(name: "slow", host: "slow.example")
            ],
            fetcher: fetcher
        )
        await viewModel.refresh()
        #expect(viewModel.state == .loaded)
        #expect(viewModel.servers.count == 1)
        #expect(viewModel.failedHosts.count == 1)
        #expect(viewModel.failedHosts.first?.kind == .timeout)
        #expect(viewModel.timedOutCount == 1)
    }

    @Test("non-timeout failure is classified .other and not counted as a timeout")
    func otherFailureClassified() async {
        struct Boom: Error {}
        let fetcher = RecordingFetcher()
        fetcher.responses["bad.example"] = .failure(Boom())
        let viewModel = TrackerBrowserViewModel(
            hosts: [TrackerHost(name: "bad", host: "bad.example")],
            fetcher: fetcher
        )
        await viewModel.refresh()
        #expect(viewModel.failedHosts.first?.kind == .other)
        #expect(viewModel.timedOutCount == 0)
    }

    @Test("only host times out → failed state, still counted")
    func onlyHostTimesOut() async {
        let fetcher = RecordingFetcher()
        fetcher.responses["slow.example"] = .failure(HotlineError.timedOut)
        let viewModel = TrackerBrowserViewModel(
            hosts: [TrackerHost(name: "slow", host: "slow.example")],
            fetcher: fetcher
        )
        await viewModel.refresh()
        if case .failed = viewModel.state {
            // ok
        } else {
            Issue.record("expected .failed, got \(viewModel.state)")
        }
        #expect(viewModel.timedOutCount == 1)
    }

    @Test("cancel keeps already-loaded servers and records no failures")
    func cancelKeepsLoaded() async {
        let fetcher = RecordingFetcher()
        fetcher.responses["a.example"] = .success([
            TrackerServer(address: "1.1.1.1", port: 5500, users: 1, name: "one", description: "")
        ])
        let viewModel = TrackerBrowserViewModel(
            hosts: [TrackerHost(name: "a", host: "a.example")],
            fetcher: fetcher
        )
        await viewModel.refresh()
        #expect(viewModel.servers.count == 1)

        // A cancelled refresh must keep the already-loaded list and must not
        // record the unfinished tracker as a failure — even though the next
        // fetch would have failed.
        fetcher.responses["a.example"] = .failure(HotlineError.timedOut)
        let task = Task { await viewModel.refresh() }
        task.cancel()
        await task.value

        #expect(viewModel.servers.count == 1)
        #expect(viewModel.failedHosts.isEmpty)
        #expect(viewModel.state == .loaded)
    }

    @Test("dedup: same server from two trackers collapses to one row with two sources")
    func dedupAcrossTrackers() async {
        let fetcher = RecordingFetcher()
        let server = TrackerServer(address: "9.9.9.9", port: 5500, users: 3, name: "shared", description: "")
        fetcher.responses["a.example"] = .success([server])
        fetcher.responses["b.example"] = .success([server])
        let viewModel = TrackerBrowserViewModel(
            hosts: [
                TrackerHost(name: "alpha", host: "a.example"),
                TrackerHost(name: "beta", host: "b.example")
            ],
            fetcher: fetcher
        )
        await viewModel.refresh()
        #expect(viewModel.servers.count == 1)
        #expect(Set(viewModel.servers.first?.sources ?? []) == Set(["alpha", "beta"]))
    }

    @Test("filter matches case-insensitive substring across name/desc/address")
    func filterMatches() async {
        let fetcher = RecordingFetcher()
        fetcher.responses["a.example"] = .success([
            TrackerServer(address: "10.0.0.1", port: 5500, users: 1, name: "Alpha", description: "irc server"),
            TrackerServer(address: "10.0.0.2", port: 5500, users: 1, name: "Beta", description: "chat"),
            TrackerServer(address: "10.0.0.3", port: 5500, users: 1, name: "Gamma", description: "files only")
        ])
        let viewModel = TrackerBrowserViewModel(
            hosts: [TrackerHost(name: "a", host: "a.example")],
            fetcher: fetcher
        )
        await viewModel.refresh()
        #expect(viewModel.filteredServers.count == 3)

        viewModel.filter = "IRC"
        #expect(viewModel.filteredServers.map(\.server.name) == ["Alpha"])

        viewModel.filter = "10.0.0.2"
        #expect(viewModel.filteredServers.map(\.server.name) == ["Beta"])

        viewModel.filter = "gamma"
        #expect(viewModel.filteredServers.map(\.server.name) == ["Gamma"])

        viewModel.filter = ""
        #expect(viewModel.filteredServers.count == 3)
    }

    @Test("filter trims whitespace; empty/whitespace filter shows all")
    func filterTrimsWhitespace() async {
        let fetcher = RecordingFetcher()
        fetcher.responses["a.example"] = .success([
            TrackerServer(address: "10.0.0.1", port: 5500, users: 1, name: "Alpha", description: "")
        ])
        let viewModel = TrackerBrowserViewModel(
            hosts: [TrackerHost(name: "a", host: "a.example")],
            fetcher: fetcher
        )
        await viewModel.refresh()
        viewModel.filter = "   "
        #expect(viewModel.filteredServers.count == 1)
        viewModel.filter = "  alpha  "
        #expect(viewModel.filteredServers.count == 1)
    }
}

// MARK: - Test helpers

private final class RecordingFetcher: TrackerFetcher, @unchecked Sendable {
    var responses: [String: Result<[TrackerServer], Error>] = [:]

    /// TaskGroup children call `fetchServers` concurrently — wrapped
    /// in `OSAllocatedUnfairLock` (the async-safe lock primitive) so
    /// two children writing at the same time don't drop one of the
    /// entries. Plain `NSLock` is unavailable in async contexts under
    /// Swift 6's strict concurrency.
    private let storage = OSAllocatedUnfairLock<[String]>(initialState: [])

    var invokedHosts: [String] {
        storage.withLock { $0 }
    }

    var callCount: Int { invokedHosts.count }

    func fetchServers(host: String, port: UInt16) async throws -> [TrackerServer] {
        storage.withLock { $0.append(host) }
        switch responses[host] {
        case .success(let servers):
            return servers
        case .failure(let error):
            throw error
        case .none:
            return []
        }
    }
}
