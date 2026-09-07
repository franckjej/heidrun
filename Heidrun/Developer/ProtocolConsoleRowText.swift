import Foundation
import HeidrunCore

/// Plain-text form of one protocol console row. The transcript renders
/// exactly this string (plus colour), and the header's text filter
/// matches against it — so a match always agrees with what's on screen.
@MainActor
enum ProtocolConsoleRowText {
    /// Direction arrow, time, server tag, task#, txID, name, then field
    /// summary. Columns padded so rows align in a monospace font.
    static func text(for entry: ProtocolConsoleEntry) -> String {
        let arrow: String
        switch entry.direction {
        case .outbound:
            arrow = "→"
        case .inbound:
            arrow = "←"
        }

        let nameLabel: String
        switch entry.kind {
        case .outboundRequest, .inboundPush, .inboundUnknown:
            nameLabel = entry.knownName ?? "???"
        case .inboundReply(let replyTo):
            // Reply name = the original request's name, suffixed for clarity.
            let baseName = entry.knownName
                ?? ProtocolConsoleStore.transactionName(for: replyTo)
                ?? "tx\(replyTo)"
            nameLabel = "\(baseName) reply"
        }

        let time = timestampFormatter.string(from: entry.timestamp)
        let serverTag = entry.server.isEmpty ? "?" : entry.server
        return "\(arrow)  \(time)  \(pad(serverTag, 18))  task=\(pad(String(entry.taskNumber), 6))  TX=\(pad(String(entry.transactionID), 4))  \(pad(nameLabel, 22))  \(summary(of: entry.fields))"
    }

    /// Case-insensitive substring match on the rendered row; an empty
    /// query matches everything.
    static func matches(_ entry: ProtocolConsoleEntry, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return true }
        return text(for: entry).localizedCaseInsensitiveContains(trimmed)
    }

    private static func pad(_ value: String, _ width: Int) -> String {
        if value.count >= width { return value }
        return value + String(repeating: " ", count: width - value.count)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// One-line preview of the packet payload. Known string fields
    /// (chat / nick / login / message) appear quoted; everything else
    /// collapses to `key:NB` byte counts so a busy line still fits.
    private static func summary(of fields: [PacketField]) -> String {
        if fields.isEmpty { return "[]" }
        let parts = fields.map { field -> String in
            if let preview = inlineValue(for: field) {
                return "\(keyName(for: field.key))=\(preview)"
            }
            return "\(keyName(for: field.key)):\(field.data.count)B"
        }
        return parts.joined(separator: " ")
    }

    /// Names from `HotlineObjectKey` (heidrun-protocol). Stored as a
    /// dictionary to keep the file out of SwiftLint's
    /// `switch_case_on_newline` rule. Unknown ids fall back to
    /// `f<NN>` so they're still searchable in the transcript.
    private static func keyName(for key: UInt16) -> String {
        keyNames[key] ?? "f\(key)"
    }

    private static let keyNames: [UInt16: String] = [
        // Generic header / chat fields (1xx range)
        100: "errMsg",
        101: "msg",
        102: "nick",
        103: "socket",
        104: "icon",
        105: "login",
        106: "pw",
        107: "transferID",
        108: "txSize",
        109: "param",
        110: "privs",
        112: "status",
        113: "banFlag",
        114: "chatRef",
        115: "chatSubj",
        116: "txQueue",
        152: "bannerType",
        154: "autoAgree",
        160: "version",
        162: "serverName",
        // File system (2xx range)
        200: "fileEntry",
        201: "name",
        202: "path",
        203: "resumeInfo",
        204: "folderResume",
        205: "type",
        206: "creator",
        207: "size",
        208: "created",
        209: "modified",
        210: "comment",
        211: "rename",
        212: "destPath",
        220: "itemCount",
        // User list
        300: "user",
        // Threaded news
        321: "threadList",
        322: "newsCat",
        323: "newsBundle",
        325: "newsPath",
        326: "newsID",
        327: "newsType",
        328: "newsTitle",
        329: "newsAuthor",
        330: "newsDate",
        331: "newsPrev",
        332: "newsNext",
        333: "newsBody",
        334: "newsFlags",
        335: "newsParent",
        336: "newsReply",
        337: "newsCascade",
        // Heidrun extension
        0xE000: "emoji"
    ]

    /// String-shaped fields the console renders inline as quoted
    /// previews (`key="…"`). Everything else falls back to the
    /// `key:NB` byte-count form so the row stays narrow.
    private static let inlineStringKeys: Set<UInt16> = [
        100, 101, 102, 105, 115, 162,
        201, 211,
        322, 328, 329, 333,
        0xE000
    ]
    private static let inlineNumericKeys: Set<UInt16> = [
        103, 104, 107, 108, 109, 110, 112, 113, 152, 154, 160,
        207, 220,
        326, 334, 335, 336, 337
    ]

    private static func inlineValue(for field: PacketField) -> String? {
        if inlineStringKeys.contains(field.key) {
            let text = String(data: field.data, encoding: .utf8)
                ?? String(data: field.data, encoding: .macOSRoman)
            guard let text else { return nil }
            let cleaned = text.replacingOccurrences(of: "\r", with: "↵")
            if cleaned.count > 48 { return "\"\(cleaned.prefix(45))…\"" }
            return "\"\(cleaned)\""
        }
        if inlineNumericKeys.contains(field.key) {
            if field.data.count == 2 {
                let value = field.data.reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
                return "\(value)"
            }
            if field.data.count == 4 {
                let value = field.data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                return "\(value)"
            }
        }
        return nil
    }
}
