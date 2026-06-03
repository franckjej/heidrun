import SwiftUI
import AppKit
import CommonTools

/// Toolbar items rendered by HostView. Extracted to keep HostView focused
/// on layout. Live updates flow via `HostState`'s `@Observable` conformance —
/// no `@Bindable` needed since the body only reads properties and dispatches
/// method calls.
struct HostToolbar: ToolbarContent {
    let state: HostState
    let transferCount: Int

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            TransfersToolbarButton(transferCount: transferCount)

            Button(role: .destructive) {
                state.disconnect()
            } label: {
                Image(systemName: "power")
                    .padding(.horizontal, .tiny)
            }
            .help("Disconnect")
            // Keyboard shortcut lives on the Connection menu item (FocusedConnectionCommands).
        }
    }
}

/// Toolbar button that toggles the Task Manager window: opens it when
/// closed, dismisses it when already on screen. Shows a small badge
/// with the count of currently-running transfers so the user has a
/// glanceable indicator.
private struct TransfersToolbarButton: View {
    let transferCount: Int
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button {
            toggleTaskManager()
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .symbolRenderingMode(.hierarchical)
                .overlay(alignment: .topTrailing) {
                    if transferCount > 0 {
                        Text(verbatim: "\(transferCount)")
                            .font(.caption2.bold())
                            .padding(.tiny)
                            .background(.red, in: Circle())
                            .foregroundStyle(.white)
                            .offset(x: 6, y: -6)
                    }
                }
                .padding(.horizontal, .tiny)
        }
        .help("Task Manager (⌥⌘T)")
    }

    /// SwiftUI's `openWindow(id:)` is a no-op when the window is already
    /// open — clicking the toolbar button a second time does nothing,
    /// which feels broken. We look up the live `NSWindow` by its
    /// `frameAutosaveName` (which SwiftUI seeds from the scene id) and
    /// close it ourselves when it's already on screen.
    private func toggleTaskManager() {
        if let existing = NSApp.windows.first(where: { window in
            window.identifier?.rawValue == WindowIDs.taskManager
                || window.frameAutosaveName == WindowIDs.taskManager
        }), existing.isVisible {
            existing.close()
        } else {
            openWindow(id: WindowIDs.taskManager)
        }
    }
}
