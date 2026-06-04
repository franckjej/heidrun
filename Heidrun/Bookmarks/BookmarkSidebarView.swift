import SwiftUI
import CommonTools
import HeidrunCore
import HeidrunBookmarks

/// Left pane of ConnectionForm: roster of bookmarks + toolbar.
/// Selection drives the form on the right. The hover-revealed
/// Connect button per row fires `onConnect(bookmark)` directly,
/// bypassing the form-edit flow.
struct BookmarkSidebarView: View {
    let store: BookmarkStore
    @Binding var selection: Set<Bookmark.ID>

    let onNew: () -> Void
    let onDelete: (Set<Bookmark.ID>) -> Void
    let onConnect: (Bookmark) -> Void
    let onConnectMany: ([Bookmark]) -> Void
    let onImportLegacy: () -> Void
    let onExportLegacy: () -> Void
    let onExportCSV: () -> Void
    let onDropFile: (URL) -> Void

    @State private var pendingDelete: Set<Bookmark.ID> = []

    var body: some View {
        VStack(spacing: 0) {
            if store.bookmarks.isEmpty {
                emptyState
            } else {
                // AppKit NSTableView (see BookmarkTableView): a SwiftUI
                // List/ScrollView can't give reliable click selection
                // together with a native two-finger trackpad
                // swipe-to-delete and row drag-out. Double-click a row to
                // connect; swipe (or right-click) to delete.
                BookmarkTableView(
                    bookmarks: store.bookmarks,
                    selection: $selection,
                    actions: BookmarkRowActions(
                        connect: { onConnect($0) },
                        connectMany: { onConnectMany($0) },
                        delete: { mark in pendingDelete = [mark.id] },
                        move: { ids, target in store.move(ids: ids, to: target) }
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()

            HStack(spacing: 4) {
                Button(action: onNew) {
                    Image(systemName: "plus")
                        .frame(width: 28, height: 24)
                        .contentShape(.rect)
                }
                .help("New bookmark")
                .buttonStyle(.borderless)

                Button {
                    if !selection.isEmpty { pendingDelete = selection }
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 28, height: 24)
                        .contentShape(.rect)
                }
                .help("Delete selected bookmark(s)")
                .disabled(selection.isEmpty)
                .buttonStyle(.borderless)

                Spacer()

                Menu {
                    Button("Import from Heidrun…", action: onImportLegacy)
                    Button("Export as Heidrun…", action: onExportLegacy)
                        .disabled(store.bookmarks.isEmpty)
                    Button("Export as CSV…", action: onExportCSV)
                        .disabled(store.bookmarks.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, .small)
            .padding(.vertical, .xxsmall)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let bookmarkFiles = urls.filter { $0.pathExtension == "heidrunbookmarks" }
            for fileURL in bookmarkFiles { onDropFile(fileURL) }
            return !bookmarkFiles.isEmpty
        }
        .alert(
            "Delete \(pendingDelete.count) bookmarks?",
            isPresented: Binding(
                get: { !pendingDelete.isEmpty },
                set: { if !$0 { pendingDelete = [] } }
            )
        ) {
            Button("Delete", role: .destructive) {
                onDelete(pendingDelete)
                pendingDelete = []
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = []
            }
        } message: {
            Text("This will remove the selected bookmark(s) from the list. Saved passwords stay in the keychain.")
        }
    }

    /// Shown when the roster is empty. `ContentUnavailableView` (macOS
    /// 14+) gives us a consistent system-styled empty state without
    /// hand-rolling a centered icon stack; the description nudges the
    /// user toward the two ways to populate the list — the form on the
    /// right and the import command under the ⋯ menu below.
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No bookmarks yet", systemImage: "bookmark")
        } description: {
            Text("Save a connection from the form, or import a Heidrun bookmark file from the ⋯ menu.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
