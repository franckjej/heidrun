import SwiftUI
import AppKit
import HeidrunBookmarks

/// Application Bookmarks menu. Works regardless of which window (or
/// none) is focused. Click on a live-matching bookmark fronts its
/// existing window; otherwise spawns a fresh seeded doc.
struct BookmarksMenuContent: View {
    @Environment(\.newDocument) private var newDocument
    private let store = BookmarkRegistry.shared

    var body: some View {
        if store.bookmarks.isEmpty {
            Text("No Bookmarks")
                .disabled(true)
        } else {
            ForEach(store.bookmarks) { mark in
                Button(menuLabel(for: mark)) {
                    open(mark)
                }
            }
        }

        Divider()

        Button {
            BookmarkFileActions.importLegacy(into: store) { title, message in
                BookmarkFileActions.presentAlert(title: title, message: message)
            }
        } label: {
            Label("Import from Heidrun…", systemImage: "square.and.arrow.down")
        }
        // No sidebar selection exists in this global menu, so offer a
        // per-bookmark export instead — each item writes a password-free
        // single-bookmark `.heidrunbookmarks` file.
        Menu {
            ForEach(store.bookmarks) { mark in
                Button(menuLabel(for: mark)) {
                    BookmarkFileActions.exportSelected([mark]) { title, message in
                        BookmarkFileActions.presentAlert(title: title, message: message)
                    }
                }
            }
        } label: {
            Label("Export Bookmark", systemImage: "square.and.arrow.up")
        }
        .disabled(store.bookmarks.isEmpty)
        Button {
            BookmarkFileActions.exportLegacy(from: store) { title, message in
                BookmarkFileActions.presentAlert(title: title, message: message)
            }
        } label: {
            Label("Export as Heidrun…", systemImage: "square.and.arrow.up")
        }
        .disabled(store.bookmarks.isEmpty)
        Button {
            BookmarkFileActions.exportCSV(from: store) { title, message in
                BookmarkFileActions.presentAlert(title: title, message: message)
            }
        } label: {
            Label("Export as CSV…", systemImage: "tablecells")
        }
        .disabled(store.bookmarks.isEmpty)
    }

    /// Does NOT open the on-disk `.heidrunbookmark` file as a doc —
    /// that linked the window to the UUID-named file URL which leaked
    /// into the titlebar. `BookmarkStore` is the canonical persistent
    /// store regardless of which window opened it.
    private func open(_ mark: Bookmark) {
        if let liveHandle = liveHandle(for: mark) {
            if let window = liveHandle.window {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
                return
            }
            // Live handle but lost the NSWindow pointer — fall through.
        }
        newDocument { HeidrunBookmarkDocument.seeded(with: mark.settings) }
    }

    /// Tombstoned (disconnected) handles are ignored — give the user a
    /// fresh connect instead of trying to reuse a dead TaskManager row.
    private func liveHandle(for mark: Bookmark) -> ConnectionHandle? {
        ActiveConnections.shared.connections.first { handle in
            guard handle.isLive else { return false }
            return handle.settings.address == mark.settings.address
                && handle.settings.port == mark.settings.port
                && handle.settings.login == mark.settings.login
        }
    }

    private func menuLabel(for mark: Bookmark) -> String {
        let display = mark.settings.name.isEmpty ? mark.settings.address : mark.settings.name
        return mark.settings.login.isEmpty ? display : "\(display) (\(mark.settings.login))"
    }
}
