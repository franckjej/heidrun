import SwiftUI
import HeidrunCore

/// Connect-sheet variant of the tracker browser, presented from
/// `ConnectionForm`. Thin wrapper over the shared `TrackerBrowserView`
/// in `.sheet` mode — picks hand the server back via `onPick`.
@MainActor
struct TrackerBrowser: View {
    let onPick: (TrackerServer) -> Void
    let onCancel: () -> Void

    var body: some View {
        TrackerBrowserView(mode: .sheet(onPick: onPick, onCancel: onCancel))
            .frame(width: 720, height: 480)
    }
}
