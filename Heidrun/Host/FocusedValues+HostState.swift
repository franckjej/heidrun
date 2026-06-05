import SwiftUI

/// Lets app-level commands act on whichever window is frontmost.
/// RootView publishes its HostState via `.focusedValue(\.hostState, state)`;
/// Commands read it via `@FocusedValue(\.hostState)`.
///
/// The value is stored in a WEAK box: SwiftUI's `FocusedValues` store is
/// app-lifetime and keeps the last-focused value forever, so publishing the
/// `HostState` directly leaked the whole connected scene (HostState + its
/// close guard + reconnect coordinator) past window close. Boxing it weakly
/// lets the store hold the (tiny) box without pinning the state.
final class WeakHostStateBox: @unchecked Sendable {
    weak var state: HostState?
    init(_ state: HostState?) { self.state = state }
}

struct HostStateFocusedValueKey: FocusedValueKey {
    typealias Value = WeakHostStateBox
}

extension FocusedValues {
    var hostState: HostState? {
        get { self[HostStateFocusedValueKey.self]?.state }
        set { self[HostStateFocusedValueKey.self] = newValue.map(WeakHostStateBox.init) }
    }
}
