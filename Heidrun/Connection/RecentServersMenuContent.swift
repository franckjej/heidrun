import SwiftUI
import AppKit
import HeidrunCore

/// File-menu "Recent Servers" submenu. Lists every entry in the
/// `RecentsStore`, plus a "Clear Menu" trailing item. Clicking an entry
/// either focuses an existing live window for that server or queues a
/// fresh host window via `SessionRestorationQueue` (so the keychain
/// password is honoured, matching the bookmark menu's behaviour).
///
/// Mirrors `BookmarksMenuContent`'s click semantics so the two menus
/// feel identical — a recent and a bookmark with the same identity open
/// the same way.
struct RecentServersMenuContent: View {
    @Environment(\.newDocument) private var newDocument
    /// Shared `@Observable` registry — same instance the connect form
    /// and Settings read/write, so a "Clear Menu" here is reflected in
    /// the form's recents pulldown immediately (and vice versa).
    private let recents = RecentsRegistry.shared

    var body: some View {
        if recents.entries.isEmpty {
            Text("No Recent Servers")
                .disabled(true)
        } else {
            ForEach(recents.entries, id: \.self) { entry in
                Button(menuLabel(for: entry)) {
                    open(entry)
                }
            }
            Divider()
            Button {
                recents.clear()
            } label: {
                Label("Clear Menu", systemImage: "trash")
            }
        }
    }

    private func open(_ settings: ConnectionSettings) {
        if let liveHandle = liveHandle(for: settings) {
            if let window = liveHandle.window {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                return
            }
        }
        // Re-record on selection so the clicked entry bubbles to the
        // top of the recents roster — standard "Open Recent" semantics.
        recents.record(settings)
        newDocument { HeidrunBookmarkDocument.seeded(with: settings) }
    }

    private func liveHandle(for settings: ConnectionSettings) -> ConnectionHandle? {
        ActiveConnections.shared.connections.first { handle in
            guard handle.isLive else { return false }
            return handle.settings.address == settings.address
                && handle.settings.port == settings.port
                && handle.settings.login == settings.login
        }
    }

    private func menuLabel(for settings: ConnectionSettings) -> String {
        let display = settings.name.isEmpty ? settings.address : settings.name
        return settings.login.isEmpty ? display : "\(display) (\(settings.login))"
    }
}
