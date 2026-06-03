import Foundation
import HeidrunCore

/// RFC 4180-compliant CSV writer for bookmark exports. Drops password
/// material on the floor — CSV is a human-readable, share-friendly
/// format and bookmark passwords belong in the keychain, not in a
/// text file the user might mail to themselves.
public enum BookmarkCSVWriter {

    private static let header = "Name,Address,Port,Login,Nickname,Icon"

    public static func write(_ bookmarks: [Bookmark]) -> String {
        var lines = [header]
        for mark in bookmarks {
            let settings = mark.settings
            lines.append([
                quoteIfNeeded(settings.name),
                quoteIfNeeded(settings.address),
                String(settings.port),
                quoteIfNeeded(settings.login),
                quoteIfNeeded(settings.nickname),
                String(settings.icon)
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Quote `field` per RFC 4180 when it contains `,`, `"`, `\r`,
    /// or `\n`. Doubles any embedded `"`.
    private static func quoteIfNeeded(_ field: String) -> String {
        let needsQuoting = field.contains(",")
            || field.contains("\"")
            || field.contains("\n")
            || field.contains("\r")
        guard needsQuoting else { return field }
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
