import Foundation

/// Wraps a ready-made, user-facing message in an `Error` so view models can
/// route local validation failures ("file too large", "folder is empty")
/// through the same `present(Error)` path as server/transport errors.
/// `ErrorPresenter.message(for:)` lifts `errorDescription` verbatim.
public struct PresentableError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
