import Foundation
import Testing
@testable import Heidrun

@Suite("TrackerTimeoutDefaults")
struct TrackerTimeoutDefaultsTests {
    /// A throwaway, empty `UserDefaults` suite so tests never touch the
    /// real `standard` domain. Cleared on creation to drop any value a
    /// prior run left behind.
    private func makeDefaults(_ suffix: String = #function) -> UserDefaults {
        let suiteName = "TrackerTimeoutDefaultsTests.\(suffix)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test("absent key falls back to 20 seconds")
    func absentFallsBack() {
        let defaults = makeDefaults()
        #expect(TrackerTimeoutDefaults.resolved(defaults: defaults) == .seconds(20))
    }

    @Test("a positive override is honored")
    func positiveOverride() {
        let defaults = makeDefaults()
        defaults.set(35, forKey: AppStorageKeys.trackerTimeoutSeconds)
        #expect(TrackerTimeoutDefaults.resolved(defaults: defaults) == .seconds(35))
    }

    @Test("zero or negative override falls back to 20 seconds")
    func nonPositiveFallsBack() {
        let zero = makeDefaults("zero")
        zero.set(0, forKey: AppStorageKeys.trackerTimeoutSeconds)
        #expect(TrackerTimeoutDefaults.resolved(defaults: zero) == .seconds(20))

        let negative = makeDefaults("negative")
        negative.set(-5, forKey: AppStorageKeys.trackerTimeoutSeconds)
        #expect(TrackerTimeoutDefaults.resolved(defaults: negative) == .seconds(20))
    }
}
