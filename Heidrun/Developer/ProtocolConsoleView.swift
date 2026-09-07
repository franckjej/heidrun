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
    @Environment(ActiveConnections.self) private var connections
    /// Auto-scroll to the newest entry while the user is at the
    /// tail. If they've scrolled up to read, we stop auto-following
    /// so they can hold position.
    @State private var autoScroll: Bool = true
    /// Address of the server whose lines are shown; `nil` = all.
    @State private var selectedServer: String?
    /// Substring the rendered rows must contain; empty = no text filter.
    @State private var textFilter: String = ""

    private var isFiltered: Bool {
        selectedServer != nil || !textFilter.isEmpty
    }

    private var visibleEntries: [ProtocolConsoleEntry] {
        let byServer = store.entries(for: selectedServer)
        guard !textFilter.isEmpty else { return byServer }
        return byServer.filter { ProtocolConsoleRowText.matches($0, query: textFilter) }
    }

    /// Identifies the (server, text) filter pair the transcript was built
    /// with; the text view re-renders when it changes.
    private var filterKey: String {
        "\(selectedServer ?? "")\u{1F}\(textFilter)"
    }

    /// Live connections, deduped by address, in registry order. The
    /// address is the popup tag because that's what the store stamps on
    /// each entry; the bookmark name is only the label.
    private var liveServers: [(address: String, label: String)] {
        var seen = Set<String>()
        return connections.connections.compactMap { handle in
            guard handle.isLive, seen.insert(handle.settings.address).inserted else { return nil }
            return (handle.settings.address, handle.displayName)
        }
    }

    /// Servers with lines in the buffer but no live session.
    private var historicalServers: [String] {
        let liveAddresses = Set(liveServers.map(\.address))
        return store.servers.filter { !liveAddresses.contains($0) }
    }

    /// Every selectable address, for resetting a selection that vanished.
    private var availableServers: [String] {
        liveServers.map(\.address) + historicalServers
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ProtocolConsoleTextView(
                entries: visibleEntries,
                filterKey: filterKey,
                autoScroll: $autoScroll
            )
            Divider()
            footer
        }
        .frame(minWidth: 720, minHeight: 320)
        .onChange(of: availableServers) { _, available in
            if let selectedServer, !available.contains(selectedServer) {
                self.selectedServer = nil
            }
        }
    }

    private var header: some View {
        HStack {
            Picker(selection: $selectedServer) {
                Text("All Servers").tag(String?.none)
                if !liveServers.isEmpty {
                    Divider()
                    ForEach(liveServers, id: \.address) { server in
                        Text(verbatim: server.label).tag(String?.some(server.address))
                    }
                }
                if !historicalServers.isEmpty {
                    Divider()
                    ForEach(historicalServers, id: \.self) { address in
                        Text(verbatim: address).tag(String?.some(address))
                    }
                }
            } label: {
                Text("Server")
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
            Spacer()
            TextField("Filter", text: $textFilter)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 220)
        }
        .padding(.small)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(verbatim: countLabel)
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

    /// "buffered / total", or "shown / buffered / total" while filtered.
    private var countLabel: String {
        if isFiltered {
            return "\(visibleEntries.count) / \(store.entries.count) / \(store.totalRecorded)"
        }
        return "\(store.entries.count) / \(store.totalRecorded)"
    }
}

// MARK: - NSTextView wrapper

/// Read-only `NSTextView` inside an `NSScrollView`, appending lines
/// as the store grows. Block-selectable / copyable, with attributed
/// colour spans so unknown-inbound rows stand out red while
/// outbound rows use a muted style.
private struct ProtocolConsoleTextView: NSViewRepresentable {
    let entries: [ProtocolConsoleEntry]
    /// Filter the entries were computed with; a change means the
    /// transcript is a different document and must re-render.
    let filterKey: String
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
            entries: entries,
            filterKey: filterKey,
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
        private var renderedFilterKey: String = ""

        func applyUpdate(entries: [ProtocolConsoleEntry], filterKey: String, autoScroll: Bool) {
            guard let textView, let textStorage = textView.textStorage else { return }
            // Cleared, trimmed past the head, or a different filter —
            // re-render from scratch. Cheap: ≤ 2000 entries.
            if entries.count < renderedCount || filterKey != renderedFilterKey {
                textStorage.setAttributedString(NSAttributedString())
                lastRenderedID = 0
                renderedFilterKey = filterKey
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

    /// One attributed row: `ProtocolConsoleRowText` supplies the text, this
    /// adds the font and the direction / unknown-id colour.
    private static func line(for entry: ProtocolConsoleEntry) -> NSAttributedString {
        let attr = NSMutableAttributedString(string: ProtocolConsoleRowText.text(for: entry) + "\n")
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

    private static let monospace: NSFont = {
        if let menlo = NSFont(name: "Menlo", size: 12) { return menlo }
        return NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }()
}
