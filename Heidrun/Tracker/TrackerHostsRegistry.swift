/// App-wide tracker-hosts store. Mirrors `RecentsRegistry`/
/// `BookmarkRegistry`: a single `@Observable` instance shared by the
/// tracker browser window, the in-window editor, and the legacy sheet
/// path, so a write from any surface is observed by every other.
@MainActor
enum TrackerHostsRegistry {
    static let shared = TrackerHostsStore(defaults: AppDataEnvironment.defaults)
}
