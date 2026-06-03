import SwiftUI
import AppKit
import HeidrunCore
import CommonTools

/// Developer console window — every wire transaction in/out of every
/// open connection, plain monospace, no chrome beyond what the
/// system window gives us. Designed for spotting dialect-specific
/// transaction IDs that other clients quietly accept.
///
/// The transcript is an `NSTextView` (wrapped via
/// `NSViewRepresentable`) so the user can select arbitrary text
/// blocks and copy them. The SwiftUI text-row alternative only
/// supports per-row selection, which breaks block-copy of multi-
/// transaction reports.
///
/// Row colour:
///   * outbound (→) — secondary (we sent it; always known)
///   * inbound (←) reply / push — primary
///   * inbound (←) unknown transaction id — red
struct ProtocolConsoleView: View {
    @Bindable var store = ProtocolConsoleStore.shared
    /// Auto-scroll to the newest entry while the user is at the
    /// tail. If they've scrolled up to read, we stop auto-following
    /// so they can hold position.
    @State private var autoScroll: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            ProtocolConsoleTextView(store: store, autoScroll: $autoScroll)
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 320)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(store.entries.count) / \(store.totalRecorded)")
                .foregroundStyle(.secondary)
                .font(.system(size: 11, design: .monospaced))
            Spacer()
            Toggle("Auto-scroll", isOn: $autoScroll)
                .controlSize(.small)
                .toggleStyle(.checkbox)
            Button("Clear") {
                store.clear()
            }
            .controlSize(.small)
        }
        .padding(.small)
    }
}

// MARK: - NSTextView wrapper

/// Read-only `NSTextView` inside an `NSScrollView`, appending lines
/// as the store grows. Block-selectable / copyable, with attributed
/// colour spans so unknown-inbound rows stand out red while
/// outbound rows use a muted style.
private struct ProtocolConsoleTextView: NSViewRepresentable {
    @Bindable var store: ProtocolConsoleStore
    @Binding var autoScroll: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.backgroundColor = .underPageBackgroundColor
        scroll.autohidesScrollers = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.allowsUndo = false
        textView.usesFontPanel = false
        textView.usesFindBar = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = NSColor.clear
        textView.textContainerInset = NSSize(width: 8, height: 4)
        textView.font = ProtocolConsoleTextView.monospace
        // No automatic substitutions for a packet log.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false

        scroll.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.scrollView = scroll
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.applyUpdate(
            entries: store.entries,
            autoScroll: autoScroll
        )
    }

    /// Coordinator handles incremental append so a 2000-entry buffer
    /// doesn't re-render from scratch on every push.
    @MainActor
    final class Coordinator {
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        /// Highest entry id already rendered. Anything in
        /// `store.entries` with a larger id is appended next pass;
        /// if `store.clear()` ran (count drops), we re-render the
        /// whole transcript from scratch.
        private var lastRenderedID: UInt64 = 0
        private var renderedCount: Int = 0

        func applyUpdate(entries: [ProtocolConsoleEntry], autoScroll: Bool) {
            guard let textView, let textStorage = textView.textStorage else { return }
            // Cleared or trimmed past the head — re-render from
            // scratch. Cheap: the buffer caps at 2000 entries.
            if entries.count < renderedCount {
                textStorage.setAttributedString(NSAttributedString())
                lastRenderedID = 0
            }
            // Append only the new tail.
            let newOnes = entries.drop { $0.id <= lastRenderedID }
            guard !newOnes.isEmpty else {
                renderedCount = entries.count
                return
            }
            let appended = NSMutableAttributedString()
            for entry in newOnes {
                appended.append(ProtocolConsoleTextView.line(for: entry))
            }
            textStorage.append(appended)
            lastRenderedID = entries.last?.id ?? lastRenderedID
            renderedCount = entries.count

            if autoScroll {
                textView.scrollRangeToVisible(
                    NSRange(location: textStorage.length, length: 0)
                )
            }
        }
    }

    // MARK: - Line formatting

    /// Per-entry one-line attributed string. Direction arrow, time,
    /// server tag (so multiple connections are distinguishable),
    /// task#, txID, name, then field summary.
    private static func line(for entry: ProtocolConsoleEntry) -> NSAttributedString {
        let arrow: String
        switch entry.direction {
        case .outbound:
            arrow = "→"
        case .inbound:
            arrow = "←"
        }

        let nameLabel: String
        switch entry.kind {
        case .outboundRequest:
            nameLabel = entry.knownName ?? "???"
        case .inboundPush:
            nameLabel = entry.knownName ?? "???"
        case .inboundReply(let replyTo):
            // Reply name = the original request's name, suffixed for clarity.
            let baseName = entry.knownName ?? ProtocolConsoleStore.transactionName(for: replyTo) ?? "tx\(replyTo)"
            nameLabel = "\(baseName) reply"
        case .inboundUnknown:
            nameLabel = entry.knownName ?? "???"
        }

        let time = Self.timestampFormatter.string(from: entry.timestamp)
        let summary = Self.summary(of: entry.fields)
        let serverTag = entry.server.isEmpty ? "?" : entry.server

        // Single tabular row. Tabs keep columns aligned without
        // relying on a fixed monospace metric for the whole row.
        let raw = "\(arrow)  \(time)  \(pad(serverTag, 18))  task=\(pad(String(entry.taskNumber), 6))  TX=\(pad(String(entry.transactionID), 4))  \(pad(nameLabel, 22))  \(summary)\n"

        let attr = NSMutableAttributedString(string: raw)
        let range = NSRange(location: 0, length: attr.length)
        attr.addAttribute(.font, value: monospace, range: range)
        attr.addAttribute(.foregroundColor, value: rowColor(for: entry), range: range)
        return attr
    }

    private static func rowColor(for entry: ProtocolConsoleEntry) -> NSColor {
        if entry.isUnknown { return NSColor.systemRed }
        switch entry.direction {
        case .outbound:
            return NSColor.secondaryLabelColor
        case .inbound:
            return NSColor.labelColor
        }
    }

    private static func pad(_ value: String, _ width: Int) -> String {
        if value.count >= width { return value }
        return value + String(repeating: " ", count: width - value.count)
    }

    private static let monospace: NSFont = {
        if let menlo = NSFont(name: "Menlo", size: 12) { return menlo }
        return NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }()

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
                let n = field.data.reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
                return "\(n)"
            }
            if field.data.count == 4 {
                let n = field.data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
                return "\(n)"
            }
        }
        return nil
    }
}
