import SwiftUI

/// Standalone tracker browser window. Thin wrapper over the shared
/// `TrackerBrowserView` in `.window` mode — picks auto-connect.
@MainActor
struct TrackerWindowView: View {
    var body: some View {
        TrackerBrowserView(mode: .window)
    }
}
