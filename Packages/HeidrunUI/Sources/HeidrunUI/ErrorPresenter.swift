import Foundation
import Observation
import HeidrunCore

/// Single, scene-scoped sink for user-facing errors — local or
/// server-driven. Any failure is reported here via `present`, and one
/// `.alert` at the scene root shows it. Centralises the error→message
/// mapping so callers never hand-format `String(describing:)` again.
///
/// One instance per window/scene (the connection window owns one on its
/// `ConnectionHandle`; other scenes make their own), injected through the
/// SwiftUI environment so nested views and sheets can reach it.
@Observable
@MainActor
public final class ErrorPresenter {
    public struct Presented: Identifiable, Equatable {
        public let id: UUID
        public let title: String
        public let message: String

        public init(id: UUID = UUID(), title: String, message: String) {
            self.id = id
            self.title = title
            self.message = message
        }
    }

    /// The error currently being shown, or `nil`. The scene-root alert
    /// binds to this; clearing it dismisses the alert.
    public private(set) var current: Presented?

    public init() {}

    /// Map any error to a user-facing message and present it. Pass `title`
    /// to describe the failed action (e.g. "Couldn't import bookmarks");
    /// otherwise a generic title is used.
    public func present(_ error: Error, title: String? = nil) {
        current = Presented(
            title: title ?? Self.defaultTitle,
            message: Self.message(for: error)
        )
    }

    /// Present a pre-formatted local error (no `Error` value to map).
    public func present(title: String, message: String) {
        current = Presented(title: title, message: message)
    }

    public func dismiss() {
        current = nil
    }

    static let defaultTitle = String(localized: "Something went wrong", bundle: .module)

    /// HotlineError → its `userMessage`; any `LocalizedError` → its
    /// `errorDescription`; everything else → the `NSError`
    /// `localizedDescription`.
    static func message(for error: Error) -> String {
        if let hotline = error as? HotlineError {
            return hotline.userMessage
        }
        if let described = (error as? LocalizedError)?.errorDescription {
            return described
        }
        return (error as NSError).localizedDescription
    }
}
