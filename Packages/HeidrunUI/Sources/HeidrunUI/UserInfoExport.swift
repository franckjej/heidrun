import Foundation
import SwiftUI
import UniformTypeIdentifiers
import HeidrunCore

/// Drag payload for a user → Finder, exporting the *full* info. A promise:
/// the server round-trip (`fetch`) runs only when the drag is dropped, and
/// the result is written as a `.txt`. Used when the user list has a fetch
/// closure wired; otherwise the row falls back to a basic `TextFileExport`.
public struct UserInfoExport: Transferable {
    public let user: User
    public let fetch: @Sendable (User) async throws -> UserInfo

    public init(user: User, fetch: @escaping @Sendable (User) async throws -> UserInfo) {
        self.user = user
        self.fetch = fetch
    }

    public static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { export in
            let info = try await export.fetch(export.user)
            let base = export.user.nickname.isEmpty ? "User" : export.user.nickname
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(TextFileExport.sanitize(base))
                .appendingPathExtension("txt")
            try UserInfoText.format(info).write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
