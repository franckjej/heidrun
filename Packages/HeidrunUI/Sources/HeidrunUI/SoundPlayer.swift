import Foundation
import AppKit

/// Loads and plays the bundled `.aiff` cues. Single shared instance — NSSound
/// caches its decoded buffer per object, so we keep one preloaded NSSound per
/// cue and replay it. Honours the `Heidrun.soundsEnabled` master flag and a
/// per-cue flag (both @AppStorage in Settings); `play(_:)` is a no-op unless
/// both are on.
@MainActor
public final class SoundPlayer {
    public static let shared = SoundPlayer()

    nonisolated public static let enabledDefaultsKey = "Heidrun.soundsEnabled"

    private var cache: [SoundCue: NSSound] = [:]

    private init() {}

    /// UserDefaults key of the per-cue switch.
    nonisolated public static func defaultsKey(for cue: SoundCue) -> String {
        "Heidrun.sound.\(cue.rawValue).enabled"
    }

    /// Global and per-cue switch both on. Reads UserDefaults on every call so
    /// Settings changes apply immediately.
    nonisolated public static func isEnabled(_ cue: SoundCue, in defaults: UserDefaults = .standard) -> Bool {
        flag(enabledDefaultsKey, in: defaults) && flag(defaultsKey(for: cue), in: defaults)
    }

    public func play(_ cue: SoundCue) {
        guard Self.isEnabled(cue) else { return }
        preview(cue)
    }

    /// Plays regardless of the switches — for the Settings preview.
    public func preview(_ cue: SoundCue) {
        guard let sound = loadIfNeeded(cue) else { return }
        // NSSound.play() returns false if the sound is already playing.
        // Stop+rewind so rapid repeats (multiple chat lines) sound right.
        if sound.isPlaying { sound.stop() }
        sound.currentTime = 0
        sound.play()
    }

    // Unset defaults to on (`bool(forKey:)` would return false).
    nonisolated private static func flag(_ key: String, in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }

    private func loadIfNeeded(_ cue: SoundCue) -> NSSound? {
        if let cached = cache[cue] { return cached }
        guard let url = Bundle.module.url(
            forResource: cue.resourceName,
            withExtension: "aiff"
        ) else {
            FileHandle.standardError.write(Data(
                "[SoundPlayer] missing resource \(cue.resourceName).aiff\n".utf8
            ))
            return nil
        }
        guard let sound = NSSound(contentsOf: url, byReference: false) else {
            FileHandle.standardError.write(Data(
                "[SoundPlayer] could not initialise NSSound for \(cue.resourceName)\n".utf8
            ))
            return nil
        }
        cache[cue] = sound
        return sound
    }
}
