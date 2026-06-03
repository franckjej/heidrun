import HeidrunCore

/// How a `TrackerBrowserView` presents and what a server pick does.
@MainActor
enum TrackerBrowserMode {
    /// Standalone window. A pick auto-connects: resolves the login via
    /// `TrackerPickResolver`, enqueues a `ConnectionSettings` on
    /// `SessionRestorationQueue`, and opens a fresh host window.
    case window

    /// Embedded sheet (inside ConnectionForm). A pick hands the chosen
    /// `TrackerServer` back via `onPick` and the host dismisses the
    /// sheet; `onCancel` runs when the user cancels.
    case sheet(onPick: (TrackerServer) -> Void, onCancel: () -> Void)
}
