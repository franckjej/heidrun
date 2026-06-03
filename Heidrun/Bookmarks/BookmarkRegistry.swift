import HeidrunBookmarks

/// App-wide bookmark store. Lives in the host (not the library) so
/// `HeidrunBookmarks` stays stateless and reusable — the host owns
/// the singleton shape. Sidebar, connection form, and the application
/// "Bookmarks" command menu all read/write through this instance so
/// every surface observes the same `@Observable` state.
@MainActor
enum BookmarkRegistry {
    static let shared = BookmarkStore(
        defaults: AppDataEnvironment.defaults,
        bookmarksDirectoryURL: AppDataEnvironment.bookmarksDirectoryURL
    )
}
