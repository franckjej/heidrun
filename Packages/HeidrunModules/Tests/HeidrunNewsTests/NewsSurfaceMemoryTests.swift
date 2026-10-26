import Foundation
import Testing
@testable import HeidrunNews

@Suite("NewsSurfaceMemory")
struct NewsSurfaceMemoryTests {
    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "NewsSurfaceMemoryTests.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suiteName))
    }

    @Test("records the pick per server")
    func recordsPerServer() throws {
        let defaults = try makeDefaults()
        let serverKey = NewsSurfaceMemory.serverKey(address: "Hotline.Example.org", port: 5500)
        let otherKey = NewsSurfaceMemory.serverKey(address: "other.example.org", port: 5500)

        #expect(NewsSurfaceMemory.surface(for: serverKey, defaults: defaults) == nil)
        NewsSurfaceMemory.record(.board, for: serverKey, defaults: defaults)
        #expect(NewsSurfaceMemory.surface(for: serverKey, defaults: defaults) == .board)
        #expect(NewsSurfaceMemory.surface(for: "hotline.example.org:5500", defaults: defaults) == .board)
        #expect(NewsSurfaceMemory.surface(for: otherKey, defaults: defaults) == nil)
    }

    @Test("a remembered pick overrides the default", arguments: [
        (NewsSurface?.none, NewsDefaultSurface.automatic, NewsDefaultSurface.automatic),
        (.board, .automatic, .board),
        (.threaded, .board, .threaded)
    ])
    func overrides(remembered: NewsSurface?, preference: NewsDefaultSurface, expected: NewsDefaultSurface) {
        #expect(preference.overridden(by: remembered) == expected)
    }
}
