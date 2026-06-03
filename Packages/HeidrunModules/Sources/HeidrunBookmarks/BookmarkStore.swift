import Foundation
import Observation
import HeidrunCore

/// Persists the user's curated server bookmarks as one
/// `.heidrunbookmark` file per entry in a known directory. File format
/// matches what `HeidrunBookmarkDocument` writes through `DocumentGroup`,
/// so a bookmark saved via File → Save As lands in this directory and
/// shows up in the sidebar (and vice versa).
///
/// Distinct from `RecentsStore` (a transient MRU) — bookmarks are
/// user-authored and never auto-evicted.
///
/// On first init the legacy `Heidrun.bookmarks` UserDefaults blob (if
/// any) is migrated: each entry is written out as a file, then the
/// defaults key is cleared.
@Observable
@MainActor
public final class BookmarkStore {
    /// Kept around for the one-shot migration; never written going forward.
    public static let storageKey = "Heidrun.bookmarks"

    public private(set) var bookmarks: [Bookmark]
    private let defaults: UserDefaults
    public let bookmarksDirectoryURL: URL

    public init(
        defaults: UserDefaults = .standard,
        bookmarksDirectoryURL: URL? = nil
    ) {
        self.defaults = defaults
        self.bookmarksDirectoryURL = bookmarksDirectoryURL ?? Self.defaultBookmarksDirectory()

        // Failing here means we can't persist; bookmarks stay in-memory
        // for this session (better than crashing the app).
        try? FileManager.default.createDirectory(
            at: self.bookmarksDirectoryURL,
            withIntermediateDirectories: true
        )

        Self.migrateFromDefaultsIfNeeded(
            defaults: defaults,
            into: self.bookmarksDirectoryURL
        )

        self.bookmarks = Self.loadFromDirectory(self.bookmarksDirectoryURL)
    }

    /// Same-id existing entry → updates in place.
    public func add(_ bookmark: Bookmark) {
        if let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[index] = bookmark
        } else {
            bookmarks.append(bookmark)
        }
        writeFile(for: bookmark)
    }

    /// No-op when no matching id — callers can `add` to insert.
    public func update(_ bookmark: Bookmark) {
        guard let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        bookmarks[index] = bookmark
        writeFile(for: bookmark)
    }

    public func remove(id: UUID) {
        guard let index = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        let removed = bookmarks.remove(at: index)
        deleteFile(for: removed)
    }

    public func contains(id: UUID) -> Bool {
        bookmarks.contains { $0.id == id }
    }

    /// Matches on `(name, address, port, login)`. `nickname` / `icon`
    /// are intentionally not in the key. Used by the form to badge a
    /// typed-out server as "already saved".
    public func bookmark(matching settings: ConnectionSettings) -> Bookmark? {
        bookmarks.first { isSameBookmark($0.settings, settings) }
    }

    /// First bookmark whose `(address, port)` matches — ignoring login
    /// and name. Tracker-pick path: the listing only carries
    /// `(address, port)` and we need the user's stored login for that
    /// host. Multiple matches → first in store order.
    public func bookmark(forAddress address: String, port: UInt16) -> Bookmark? {
        let needle = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return bookmarks.first { mark in
            mark.settings.address.lowercased() == needle
                && mark.settings.port == port
        }
    }

    /// Pin `sha256` after a trust-on-first-use acceptance so the next
    /// connect verifies against the pin instead of re-prompting. No-op
    /// for ad-hoc connections that were never bookmarked.
    public func updatePinnedCertificate(
        address: String, port: UInt16, login: String, sha256: String
    ) {
        let needle = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let index = bookmarks.firstIndex(where: { mark in
            mark.settings.address.lowercased() == needle
                && mark.settings.port == port
                && mark.settings.login == login
        }) else { return }
        bookmarks[index].settings.pinnedCertificateSHA256 = sha256
        writeFile(for: bookmarks[index])
    }

    /// Drop-in replacement for the whole roster (legacy import). Every
    /// prior file is deleted before re-writing — a bookmark dropped via
    /// "Replace" must not linger on disk just because its filename
    /// happened not to be overwritten.
    public func replaceAll(with replacements: [Bookmark]) {
        for mark in bookmarks {
            deleteFile(for: mark)
        }
        bookmarks = replacements
        for mark in replacements {
            writeFile(for: mark)
        }
    }

    /// On-disk URL, or `nil` for in-memory-only bookmarks.
    public func url(for bookmark: Bookmark) -> URL? {
        let candidate = fileURL(for: bookmark)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// Re-scan the directory — covers Finder-dropped `.heidrunbookmark`
    /// files or direct-write imports.
    public func refreshFromDisk() {
        bookmarks = Self.loadFromDirectory(bookmarksDirectoryURL)
    }

    // MARK: Private

    private func isSameBookmark(_ lhs: ConnectionSettings, _ rhs: ConnectionSettings) -> Bool {
        lhs.name == rhs.name
            && lhs.address == rhs.address
            && lhs.port == rhs.port
            && lhs.login == rhs.login
    }

    private func fileURL(for bookmark: Bookmark) -> URL {
        bookmarksDirectoryURL.appendingPathComponent(
            "\(bookmark.id.uuidString).heidrunbookmark"
        )
    }

    private func writeFile(for bookmark: Bookmark) {
        do {
            let data = try Self.encoder.encode(bookmark)
            try data.write(to: fileURL(for: bookmark), options: .atomic)
        } catch {
            // Best-effort; never crash over persistence. In-memory state
            // still reflects the edit.
        }
    }

    private func deleteFile(for bookmark: Bookmark) {
        try? FileManager.default.removeItem(at: fileURL(for: bookmark))
    }

    // MARK: Loading + migration

    private static func defaultBookmarksDirectory() -> URL {
        let fileManager = FileManager.default
        let supportDir: URL
        do {
            supportDir = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            // Application Support resolution can fail in CI / sandbox
            // edges — fall back to tmpdir.
            supportDir = fileManager.temporaryDirectory
        }
        return supportDir
            .appendingPathComponent("Heidrun", isDirectory: true)
            .appendingPathComponent("Bookmarks", isDirectory: true)
    }

    private static func loadFromDirectory(_ dir: URL) -> [Bookmark] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }
        let bookmarkFiles = contents.filter { $0.pathExtension == "heidrunbookmark" }
        // Stable order by filename so the sidebar doesn't reshuffle across
        // launches (UUID prefixes sort lexicographically).
        let sortedFiles = bookmarkFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return sortedFiles.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(Bookmark.self, from: data)
        }
    }

    /// Idempotent — runs only while the legacy key is still present.
    private static func migrateFromDefaultsIfNeeded(
        defaults: UserDefaults,
        into bookmarksDirectoryURL: URL
    ) {
        guard let data = defaults.data(forKey: storageKey),
              let legacy = try? JSONDecoder().decode([Bookmark].self, from: data) else {
            return
        }
        for bookmark in legacy {
            let url = bookmarksDirectoryURL.appendingPathComponent(
                "\(bookmark.id.uuidString).heidrunbookmark"
            )
            if let encoded = try? encoder.encode(bookmark) {
                try? encoded.write(to: url, options: .atomic)
            }
        }
        defaults.removeObject(forKey: storageKey)
    }

    // MARK: Coders

    /// Matches `HeidrunBookmarkDocument`'s on-disk format — sorted keys
    /// + pretty printing keep files git-friendly and byte-stable.
    nonisolated static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
    nonisolated static let decoder = JSONDecoder()
}
