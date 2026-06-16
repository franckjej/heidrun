import Foundation
import SwiftUI
import HeidrunCore
import HeidrunUI

public enum FilesFeature: HeidrunFeature {
    public static let identifier  = "com.heidrun.files"
    public static var displayName: String { String(localized: "Files", bundle: .module) }
    public static let systemImage = "folder"

    /// UserDefaults key for the security-scoped bookmark of the user's
    /// chosen download folder, written by the app's Settings pane. Resolved
    /// once per download to honour any change without restarting the app.
    public static let downloadFolderBookmarkKey = "Heidrun.downloadFolderBookmark"

    @MainActor
    // Note: in production HostView short-circuits the Files tab to the
    // hoisted ConnectionHandle.filesVM, which DOES wire metadataSeed.
    // This factory is only reached as a fallback — partials made by it
    // won't carry resume metadata. If that path becomes load-bearing,
    // thread a seed through the HeidrunFeature protocol contract.
    public static func makeContentView(client: any HotlineClient) -> AnyView {
        AnyView(
            FilesView(
                viewModel: FilesViewModel(
                    client: client,
                    downloadFolderURL: resolveDownloadFolder,
                    onTransferFinished: { transferState in
                        if case .completed = transferState.status {
                            SoundPlayer.shared.play(.fileDone)
                        }
                    }
                )
            )
        )
    }

    /// Resolve the user's preferred download folder from the security-scoped
    /// bookmark Settings persists. Falls back to ~/Downloads when no bookmark
    /// is set or it can no longer be resolved.
    @Sendable
    public static func resolveDownloadFolder() -> URL {
        // Under the XCTest host, never resolve the user's real Downloads
        // folder — accessing it pops a TCC "access your Downloads folder"
        // prompt that can't be granted unattended. A throwaway temp dir
        // keeps test runs prompt-free. (`XCTestConfigurationFilePath` is
        // the same test sentinel the app's TestEnvironment uses.)
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("heidrun-tests-downloads", isDirectory: true)
        }
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: downloadFolderBookmarkKey) else {
            return FilesViewModel.defaultDownloadFolder()
        }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return FilesViewModel.defaultDownloadFolder()
        }
        return url
    }
}
