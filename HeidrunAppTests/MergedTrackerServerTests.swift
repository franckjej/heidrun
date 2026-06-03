import Foundation
import Testing
@testable import Heidrun
import HeidrunCore

@MainActor
@Suite("MergedTrackerServer")
struct MergedTrackerServerTests {
    @Test("id is address:port (no grouping separators)")
    func idIsAddressPort() {
        let server = TrackerServer(address: "10.0.0.1", port: 5500, users: 0, name: "x", description: "")
        let merged = MergedTrackerServer(server: server, sources: ["hltracker"])
        #expect(merged.id == "10.0.0.1:5500")
    }

    @Test("merge of two reports collapses to one row with both sources")
    func mergeCollapses() {
        let a = TrackerServer(address: "10.0.0.1", port: 5500, users: 3, name: "x", description: "d")
        let b = TrackerServer(address: "10.0.0.1", port: 5500, users: 5, name: "x", description: "d")
        let merged = MergedTrackerServer.merge(reports: [
            (trackerName: "hltracker", servers: [a]),
            (trackerName: "preter", servers: [b])
        ])
        #expect(merged.count == 1)
        let only = merged.first
        #expect(only?.id == "10.0.0.1:5500")
        #expect(Set(only?.sources ?? []) == Set(["hltracker", "preter"]))
    }

    @Test("merge prefers the highest user count when reports differ")
    func mergePrefersHighestUsers() {
        let a = TrackerServer(address: "10.0.0.1", port: 5500, users: 3, name: "x", description: "d")
        let b = TrackerServer(address: "10.0.0.1", port: 5500, users: 7, name: "x", description: "d")
        let merged = MergedTrackerServer.merge(reports: [
            (trackerName: "hltracker", servers: [a]),
            (trackerName: "preter", servers: [b])
        ])
        #expect(merged.first?.server.users == 7)
    }

    @Test("distinct servers stay separate")
    func distinctSeparate() {
        let a = TrackerServer(address: "10.0.0.1", port: 5500, users: 1, name: "a", description: "")
        let b = TrackerServer(address: "10.0.0.2", port: 5500, users: 1, name: "b", description: "")
        let merged = MergedTrackerServer.merge(reports: [
            (trackerName: "hltracker", servers: [a, b])
        ])
        #expect(merged.count == 2)
    }

    @Test("single source reports one source name only")
    func singleSource() {
        let a = TrackerServer(address: "10.0.0.1", port: 5500, users: 1, name: "a", description: "")
        let merged = MergedTrackerServer.merge(reports: [(trackerName: "hltracker", servers: [a])])
        #expect(merged.first?.sources == ["hltracker"])
    }
}
