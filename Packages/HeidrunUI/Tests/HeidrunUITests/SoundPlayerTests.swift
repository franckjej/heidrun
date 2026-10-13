import Foundation
import Testing
@testable import HeidrunUI

@Suite("SoundPlayer")
struct SoundPlayerTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "SoundPlayerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test("every cue defaults to enabled")
    func defaultsToEnabled() {
        let defaults = makeDefaults()
        for cue in SoundCue.allCases {
            #expect(SoundPlayer.isEnabled(cue, in: defaults))
        }
    }

    @Test("per-cue switch disables only that cue")
    func perCueSwitch() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: SoundPlayer.defaultsKey(for: .chatPost))
        #expect(!SoundPlayer.isEnabled(.chatPost, in: defaults))
        #expect(SoundPlayer.isEnabled(.login, in: defaults))
    }

    @Test("global switch overrides per-cue switches")
    func globalSwitch() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: SoundPlayer.enabledDefaultsKey)
        defaults.set(true, forKey: SoundPlayer.defaultsKey(for: .login))
        #expect(!SoundPlayer.isEnabled(.login, in: defaults))
    }

    @Test("per-cue keys are unique")
    func uniqueKeys() {
        let keys = Set(SoundCue.allCases.map(SoundPlayer.defaultsKey(for:)))
        #expect(keys.count == SoundCue.allCases.count)
    }
}
