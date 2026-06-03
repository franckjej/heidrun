import SwiftUI
import UniformTypeIdentifiers
import HeidrunCore
import HeidrunBookmarks

/// SwiftUI `ReferenceFileDocument` backing the `DocumentGroup`. Each host
/// window is one — file-backed when saved, untitled while connecting.
///
/// JSON-encoded `Bookmark`, same on-disk format as `BookmarkStore`'s
/// file-backed registry; a bookmark saved here lands in the sidebar
/// roster automatically.
///
/// `@unchecked Sendable` because `ReferenceFileDocument` can't be
/// `@MainActor`-isolated; SwiftUI drives the doc on main regardless, so
/// off-main mutation is a caller bug.
final class HeidrunBookmarkDocument: ReferenceFileDocument, @unchecked Sendable {
    typealias Snapshot = Bookmark

    static let readableContentTypes: [UTType] = [.heidrunBookmark]
    static let writableContentTypes: [UTType] = [.heidrunBookmark]

    @Published var bookmark: Bookmark

    /// Form fields bind to this slice.
    var settings: ConnectionSettings {
        get { bookmark.settings }
        set { bookmark.settings = newValue }
    }

    /// Pre-form starting point — real defaults (`AppStorageKeys`) are
    /// picked up by `ConnectionForm.hydrateDefaults`.
    init() {
        self.bookmark = Bookmark(
            settings: ConnectionSettings(
                name: "",
                address: "",
                port: 5500,
                nickname: NSFullUserName(),
                login: "",
                icon: 0,
                useTLS: false,
                pinnedCertificateSHA256: nil,
                emoji: nil
            )
        )
    }

    /// Untitled doc pre-seeded with settings. `RootView.task` notices
    /// the non-empty address and routes through `autoConnectFromDocument`.
    static func seeded(with settings: ConnectionSettings) -> HeidrunBookmarkDocument {
        let document = HeidrunBookmarkDocument()
        document.bookmark.settings = settings
        return document
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.bookmark = try Self.decodeBookmark(from: data)
    }

    /// Registers an undo so DocumentGroup flags the doc as edited (which
    /// enables ⌘S). No-op when unchanged so idempotent re-Connects don't
    /// dirty the document.
    func updateBookmark(_ newValue: Bookmark, undoManager: UndoManager?) {
        let previous = bookmark
        guard previous != newValue else { return }
        bookmark = newValue
        MainActor.assumeIsolated {
            undoManager?.registerUndo(withTarget: self) { document in
                document.updateBookmark(previous, undoManager: undoManager)
            }
        }
    }

    func snapshot(contentType: UTType) throws -> Bookmark { bookmark }

    func fileWrapper(
        snapshot: Bookmark,
        configuration: WriteConfiguration
    ) throws -> FileWrapper {
        let data = try Self.encodeBookmark(snapshot)
        return FileWrapper(regularFileWithContents: data)
    }

    // MARK: Codable seam

    // Pure-Data encode/decode for tests — `ReadConfiguration` /
    // `WriteConfiguration` have no public initializers, and
    // `BookmarkStore`'s file-backed reader uses the same bytes.

    /// Sorted keys give bookmark files a stable byte order (git-diffable,
    /// deterministic round-trip tests).
    nonisolated static func encodeBookmark(_ bookmark: Bookmark) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(bookmark)
    }

    nonisolated static func decodeBookmark(from data: Data) throws -> Bookmark {
        try JSONDecoder().decode(Bookmark.self, from: data)
    }
}
