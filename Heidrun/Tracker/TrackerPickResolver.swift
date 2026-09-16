import CommonTools
import HeidrunBookmarks
import HeidrunCore

/// Resolves the login a tracker-picked server should connect with,
/// without any UI. Lookup order: a matching bookmark's login, then any
/// saved keychain login for the address, then empty (Hotline guest
/// convention). Shared by the tracker window's auto-connect path and
/// `ConnectionForm.hydrate(fromTrackerPick:)` so both agree.
@MainActor
enum TrackerPickResolver {
    static func resolveLogin(address: String, port: UInt16) -> String {
        if let mark = BookmarkRegistry.shared.bookmark(forAddress: address, port: port) {
            return mark.settings.login
        }
        if let login = KeychainPasswordStore.findAnyLogin(forAddress: address, port: port) {
            return login
        }
        return ""
    }

    /// Settings for connecting to a tracker pick: the server's name and
    /// address, the resolved login, and the caller's identity defaults.
    /// Records the pick in `recents` when the user remembers recents,
    /// so tracker connects show up next to form and URL connects.
    static func settings(
        forPick server: TrackerServer,
        nickname: String,
        iconID: Int,
        recordingIn recents: RecentsStore,
        rememberRecents: Bool
    ) -> ConnectionSettings {
        let settings = ConnectionSettings(
            name: server.name,
            address: server.address,
            port: server.port,
            nickname: nickname,
            login: resolveLogin(address: server.address, port: server.port),
            icon: UInt16(clamping: iconID)
        )
        if rememberRecents { recents.record(settings) }
        return settings
    }
}
