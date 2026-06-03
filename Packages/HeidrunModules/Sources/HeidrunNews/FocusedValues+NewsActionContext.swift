import SwiftUI

/// Bridges the focused threaded-news view's `NewsActionContext` to the
/// macOS "News" command menu. `ThreadedNewsScreen` publishes it via
/// `.focusedValue(\.newsActionContext, ctx)`; the app target's
/// `NewsCommands` reads it via `@FocusedValue(\.newsActionContext)`.
/// `nil` when no news view is focused, which disables every News command.
///
/// Lives in HeidrunNews (not the app target) because the publisher
/// `ThreadedNewsScreen` is in this package and can't see app-target
/// code — so the key + the accessor are `public` for the app to consume.
public struct NewsActionContextFocusedValueKey: FocusedValueKey {
    public typealias Value = NewsActionContext
}

extension FocusedValues {
    public var newsActionContext: NewsActionContext? {
        get { self[NewsActionContextFocusedValueKey.self] }
        set { self[NewsActionContextFocusedValueKey.self] = newValue }
    }
}
