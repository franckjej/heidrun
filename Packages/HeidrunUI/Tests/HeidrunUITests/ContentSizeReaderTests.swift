import Testing
import Foundation
import CommonTools
@testable import HeidrunUI

@Suite struct ContentSizeReaderTests {
    /// Isolated suite (`UserDefaults` is process-global).
    private func makeDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func namedPresetReadsDirectly() {
        let defaults = makeDefaults("contentReader.named")
        defaults.set("comfortable", forKey: ContentSizeReader.presetStorageKey)
        #expect(ContentSizeReader.current(in: defaults).preset == .comfortable)
    }

    @Test func systemModeResolvesFromOSSidebarSizeKey() {
        let defaults = makeDefaults("contentReader.systemSmall")
        defaults.set("system", forKey: ContentSizeReader.presetStorageKey)
        defaults.set(1, forKey: ContentSize.DensityMode.systemSidebarSizeDefaultsKey)
        #expect(ContentSizeReader.current(in: defaults).preset == .compact)

        defaults.set(3, forKey: ContentSize.DensityMode.systemSidebarSizeDefaultsKey)
        #expect(ContentSizeReader.current(in: defaults).preset == .comfortable)
    }
}
