import AppKit
import Foundation
import UniformTypeIdentifiers
import CommonTools
import HeidrunBookmarks

/// Shared NSPanel + keychain plumbing for bookmark import/export.
/// Used by both the sidebar's ⋯ menu and the application "Bookmarks"
/// menu so the two surfaces behave identically — the user opens the
/// same dialogs, hits the same UTType filter, and writes/reads to the
/// same keychain.
///
/// Each method runs its panel modally, performs the work, and
/// surfaces failures through an `(title, message)` closure so callers
/// can decide whether to present a SwiftUI alert or an NSAlert.
/// Success/cancel is reported via the return value so callers can
/// follow up (e.g. reset the form after a destructive import).
@MainActor
enum BookmarkFileActions {
    /// Show the import panel, decode the file, replace the roster.
    /// Returns the imported bookmark count on success, `nil` on cancel
    /// or failure (errors go through `onError`).
    @discardableResult
    static func importLegacy(
        into store: BookmarkStore,
        onError: (String, String) -> Void
    ) -> Int? {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import bookmarks")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if let contentType = UTType(filenameExtension: "heidrunbookmarks") {
            panel.allowedContentTypes = [contentType]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let imported = try BookmarkArchiver.unarchive(data) { password, key in
                let keychainKey = KeychainPasswordStore.Key.canonical(
                    address: key.address,
                    port: key.port,
                    login: key.login
                )
                KeychainPasswordStore.saveOrLog(password, for: keychainKey)
            }
            store.replaceAll(with: imported)
            return imported.count
        } catch let error as BookmarkArchiveError {
            onError(String(localized: "Couldn't import bookmarks"), error.errorDescription ?? String(localized: "Unknown error."))
            return nil
        } catch {
            onError(String(localized: "Couldn't import bookmarks"), error.localizedDescription)
            return nil
        }
    }

    /// Show the save panel, archive the roster as `.heidrunbookmarks`.
    /// Returns `true` on success, `false` on cancel or failure.
    @discardableResult
    static func exportLegacy(
        from store: BookmarkStore,
        onError: (String, String) -> Void
    ) -> Bool {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export bookmarks")
        panel.nameFieldStringValue = "Heidrun Bookmarks"
        if let contentType = UTType(filenameExtension: "heidrunbookmarks") {
            panel.allowedContentTypes = [contentType]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            let data = try BookmarkArchiver.archive(store.bookmarks) { key in
                let keychainKey = KeychainPasswordStore.Key.canonical(
                    address: key.address,
                    port: key.port,
                    login: key.login
                )
                // Route through the session cache so a bookmark whose
                // password the user already unlocked this session
                // (e.g. by connecting earlier) doesn't re-prompt for
                // Touch ID. The first export of an un-unlocked
                // bookmark still pops one auth sheet per credential —
                // acceptable for the rare export gesture.
                let exportLabel = key.address
                return KeychainPasswordStore.cachedOrRead(
                    for: keychainKey,
                    prompt: String(localized: "Export saved password for \(exportLabel)")
                )
            }
            try data.write(to: url)
            return true
        } catch {
            onError(String(localized: "Couldn't export bookmarks"), error.localizedDescription)
            return false
        }
    }

    /// Show the save panel, write the roster as RFC-4180 CSV.
    @discardableResult
    static func exportCSV(
        from store: BookmarkStore,
        onError: (String, String) -> Void
    ) -> Bool {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export bookmarks as CSV")
        panel.nameFieldStringValue = "bookmarks"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        let text = BookmarkCSVWriter.write(store.bookmarks)
        do {
            try Data(text.utf8).write(to: url)
            return true
        } catch {
            onError(String(localized: "Couldn't export CSV"), error.localizedDescription)
            return false
        }
    }

    /// AppKit-modal error presenter — used by surfaces (like the
    /// application menu) that don't have a SwiftUI alert binding
    /// nearby. The title/message contract matches what the helpers
    /// above hand to their `onError` closures, so callers can pass
    /// this directly.
    static func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
