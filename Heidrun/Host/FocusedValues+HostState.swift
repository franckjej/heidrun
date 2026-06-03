import SwiftUI

/// Lets app-level commands act on whichever window is frontmost.
/// RootView publishes its HostState via `.focusedValue(\.hostState, state)`;
/// Commands read it via `@FocusedValue(\.hostState)`.
struct HostStateFocusedValueKey: FocusedValueKey {
    typealias Value = HostState
}

extension FocusedValues {
    var hostState: HostState? {
        get { self[HostStateFocusedValueKey.self] }
        set { self[HostStateFocusedValueKey.self] = newValue }
    }
}
