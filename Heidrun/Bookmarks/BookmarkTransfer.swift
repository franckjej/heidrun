import Foundation
import SwiftUI
import UniformTypeIdentifiers
import HeidrunCore
import HeidrunBookmarks

extension UTType {
    /// The `.heidrunbookmarks` archive type, declared in the app's
    /// `UTExportedTypeDeclarations`. Multi-bookmark archive used for
    /// import / export sharing.
    static let heidrunBookmarks = UTType(exportedAs: "org.tastybytes.heidrun.bookmarks")
    /// Single-bookmark document type backing `HeidrunBookmarkDocument`
    /// — the file format the `DocumentGroup` reads + writes. One
    /// `ConnectionSettings` per file, JSON-encoded.
    static let heidrunBookmark = UTType(exportedAs: "org.tastybytes.heidrun.bookmark")
}

/// The sole element of `selection` when exactly one is selected; `nil`
/// for an empty or multi selection. Lets the connect form keep its
/// single-bookmark edit/save behaviour atop a multi-select sidebar.
func singleBookmarkID(in selection: Set<Bookmark.ID>) -> Bookmark.ID? {
    selection.count == 1 ? selection.first : nil
}

/// Drag payload for one or more bookmarks → a `.heidrunbookmarks` file.
/// Passwords are deliberately omitted (no keychain read, no Touch ID);
/// the "Export…" menu remains the with-password backup path.
struct BookmarkExport: Transferable {
    let bookmarks: [Bookmark]

    /// Base file name (no extension) Finder shows for the dropped file.
    var suggestedFileName: String {
        guard bookmarks.count == 1 else {
            return "\(bookmarks.count) Bookmarks"
        }
        let settings = bookmarks[0].settings
        let trimmedName = settings.name.trimmingCharacters(in: .whitespaces)
        return Self.sanitize(trimmedName.isEmpty ? settings.address : trimmedName)
    }

    /// Archive `bookmarks` with empty passwords (no keychain access).
    static func archiveData(for bookmarks: [Bookmark]) throws -> Data {
        try BookmarkArchiver.archive(bookmarks) { _ in nil }
    }

    /// Map a tracker listing to a password-free bookmark.
    static func bookmark(from server: TrackerServer) -> Bookmark {
        Bookmark(settings: ConnectionSettings(
            name: server.name,
            address: server.address,
            port: server.port
        ))
    }

    /// Synchronous AppKit drag source: writes the `.heidrunbookmarks`
    /// archive (no passwords) immediately. `.onDrag { … }` returns this —
    /// reliable in Lists/Tables where `.draggable` gets swallowed.
    func makeItemProvider() -> NSItemProvider {
        let base = suggestedFileName
        let marks = bookmarks
        let provider = NSItemProvider()
        provider.suggestedName = base
        provider.registerFileRepresentation(
            forTypeIdentifier: UTType.heidrunBookmarks.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            do {
                let data = try BookmarkExport.archiveData(for: marks)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(base)
                    .appendingPathExtension("heidrunbookmarks")
                try data.write(to: url, options: .atomic)
                completion(url, false, nil)
            } catch {
                completion(nil, false, error)
            }
            return nil
        }
        return provider
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .heidrunBookmarks) { export in
            let data = try archiveData(for: export.bookmarks)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(export.suggestedFileName)
                .appendingPathExtension("heidrunbookmarks")
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }

    /// Replace path-hostile characters so the name is a valid filename.
    private static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "Bookmark" : cleaned
    }
}
