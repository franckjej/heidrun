/// App-wide recents store. Mirrors `BookmarkRegistry`: a single
/// `@Observable` instance shared by the connection form, the File
/// menu's "Recent Servers" submenu, and the Settings "Clear" action,
/// so a write from any surface (record on connect, clear from the
/// menu, clear from Settings) is observed by every other surface
/// without a re-init dance.
@MainActor
enum RecentsRegistry {
    static let shared = RecentsStore(defaults: AppDataEnvironment.defaults)
}
