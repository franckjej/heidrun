import SwiftUI
import CommonTools
import HeidrunCore
import HeidrunBookmarks

/// Floats over the host's root view when the user double-clicks a
/// `.heidrunbookmarks` file in Finder. Decodes the archive on the
/// main actor (the file is small — a few KB at most), previews what
/// it contains, and lets the user choose between **Append** and
/// **Replace** before committing to `BookmarkStore`. The reusable
/// path for menu-driven import lives in `BookmarkFileActions`; this
/// sheet exists specifically so the OS-driven open path doesn't make
/// a destructive change without the user confirming.
struct BookmarksImportSheet: View {
    let url: URL
    let onDismiss: () -> Void

    private let store = BookmarkRegistry.shared

    @State private var imported: [Bookmark] = []
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import bookmarks?")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 4) {
                Text(url.lastPathComponent)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let loadError {
                    Text(loadError)
                        .font(.callout)
                        .foregroundStyle(.red)
                } else {
                    Text("\(imported.count) bookmarks found.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    previewList
                }
            }

            HStack {
                Button("Cancel", role: .cancel, action: onDismiss)
                Spacer()
                if loadError == nil {
                    Button("Append", action: append)
                        .keyboardShortcut(.defaultAction)
                    Button("Replace All", role: .destructive, action: replaceAll)
                }
            }
        }
        .padding(.medium)
        .frame(width: 460)
        .closeOnCmdW(onDismiss)
        .task { await load() }
    }

    @ViewBuilder
    private var previewList: some View {
        if !imported.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(imported.prefix(6)) { bookmark in
                    HStack(spacing: 6) {
                        Image(systemName: "bookmark")
                            .foregroundStyle(.secondary)
                        Text(bookmark.settings.name.isEmpty
                             ? bookmark.settings.address
                             : bookmark.settings.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("(\(bookmark.settings.address):\(bookmark.settings.port.formatted(.number.grouping(.never))))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if imported.count > 6 {
                    Text("…and \((imported.count - 6).formatted(.number.grouping(.never))) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, .xxsmall)
        }
    }

    private func load() async {
        let url = self.url
        let result: Result<[Bookmark], Error> = await Task.detached {
            do {
                let data = try Data(contentsOf: url)
                let bookmarks = try BookmarkArchiver.unarchive(data) { _, _ in
                    // Keychain side-effects are deferred until the user
                    // actually confirms — we don't want a cancelled
                    // import to leave saved passwords behind.
                }
                return .success(bookmarks)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let bookmarks):
            self.imported = bookmarks
        case .failure(let error):
            self.loadError = (error as? BookmarkArchiveError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func append() {
        commitKeychain()
        for bookmark in imported {
            store.add(bookmark)
        }
        onDismiss()
    }

    private func replaceAll() {
        commitKeychain()
        store.replaceAll(with: imported)
        onDismiss()
    }

    /// Re-runs the archive unarchive once we've decided to keep the
    /// import, this time letting the `keychainSave` callback land. We
    /// do the decode twice rather than buffering passwords because
    /// keeping passwords in memory across a sheet's lifetime — even a
    /// short one — is the kind of thing a future security review
    /// would (rightly) flag.
    private func commitKeychain() {
        guard let data = try? Data(contentsOf: url) else { return }
        _ = try? BookmarkArchiver.unarchive(data) { password, key in
            let keychainKey = KeychainPasswordStore.Key.canonical(
                address: key.address,
                port: key.port,
                login: key.login
            )
            KeychainPasswordStore.saveOrLog(password, for: keychainKey)
        }
    }
}
