import Foundation
import Observation

/// Per-connection unread counts keyed by feature identifier, plus a
/// pulse token the UI animates on. Owned by `ConnectionHandle`.
@MainActor
@Observable
final class AttentionState {
    private(set) var counts: [String: Int] = [:]
    /// Increments on every raise and on every growing `set`.
    private(set) var pulseToken: Int = 0
    /// True while the window title is mid-flash; driven by the host view.
    var titlePulsing = false

    var total: Int { counts.values.reduce(0, +) }

    func raise(_ featureID: String, by delta: Int = 1) {
        guard delta > 0 else { return }
        counts[featureID, default: 0] += delta
        pulseToken += 1
    }

    /// Authoritative count (Messages uses this). Pulses only when it grows.
    func set(_ featureID: String, to count: Int) {
        let previous = counts[featureID] ?? 0
        if count > 0 {
            counts[featureID] = count
        } else {
            counts[featureID] = nil
        }
        if count > previous { pulseToken += 1 }
    }

    func clear(_ featureID: String) {
        counts[featureID] = nil
    }

    func clearAll() {
        counts = [:]
    }
}
