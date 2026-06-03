import CommonTools
import HeidrunBookmarks

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
}
