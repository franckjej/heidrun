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

    @Test func systemModeReadsResolvedMirror() {
        let defaults = makeDefaults("contentReader.systemMirror")
        defaults.set("system", forKey: ContentSizeReader.presetStorageKey)
        defaults.set("compact", forKey: ContentSizeReader.systemResolvedKey)
        #expect(ContentSizeReader.current(in: defaults).preset == .compact)
    }

    @Test func systemModeWithoutMirrorFallsBackToStandard() {
        let defaults = makeDefaults("contentReader.systemNoMirror")
        defaults.set("system", forKey: ContentSizeReader.presetStorageKey)
        #expect(ContentSizeReader.current(in: defaults).preset == .standard)
    }
}
