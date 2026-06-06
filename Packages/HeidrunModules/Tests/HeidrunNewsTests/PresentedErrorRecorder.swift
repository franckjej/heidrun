import Foundation

/// Test double for a view-model's `present: (Error) -> Void` closure —
/// captures the last error so a test can assert a failure surfaced,
/// replacing the old `lastError` property assertions.
@MainActor
final class PresentedErrorRecorder {
    private(set) var last: Error?
    func record(_ error: Error) { last = error }
}
