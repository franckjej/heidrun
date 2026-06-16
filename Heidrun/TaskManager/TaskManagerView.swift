import SwiftUI
import AppKit
import HeidrunCore
import HeidrunFiles
import CommonTools

/// Activity-Monitor-style window: live server connections (top) + every
/// in-flight or recently-finished transfer across them (bottom). Driven
/// entirely by `ActiveConnections`; each row reflects observable state on
/// a `ConnectionHandle` — no extra polling.
struct TaskManagerView: View {
    @Environment(ActiveConnections.self) private var connections
    @Environment(\.openWindow) private var openWindow
    @Environment(\.newDocument) private var newDocument
    @State private var selectedConnection: ConnectionHandle.ID?
    @State private var selectedTransfer: AggregatedTransfer.ID?

    /// Snapshot ticked by `refreshLoop` on STRUCTURAL changes only —
    /// any reassignment would rebuild the Table view tree and drop the
    /// in-flight NSTableView selection.
    @State private var aggregatedSnapshot: [AggregatedTransfer] = []

    /// Sampled in `refreshLoop` instead of read directly from the body
    /// — calling `activeCount(handle)` in column scope subscribes the
    /// whole body to `filesVM` invalidations and rebuilds the Table on
    /// every byte.
    @State private var transferCountsByHandle: [ConnectionHandle.ID: Int] = [:]

    var body: some View {
        VSplitView {
            connectionsPane
                .frame(minHeight: 140, idealHeight: 180)
            transfersPane
                .frame(minHeight: 200)
        }
        .frame(minWidth: 640, minHeight: 420)
        .toolbar { toolbarItems }
        .navigationTitle("Task Manager")
        .task { await refreshLoop() }
    }

    /// Ticks the snapshot only when identity-or-status changes — bytes
    /// alone don't qualify. Cells fetch up-to-the-moment bytes/speed
    /// through `liveState(for:)` so visuals still update.
    private func refreshLoop() async {
        while !Task.isCancelled {
            let next = aggregated
            if structuralKey(of: next) != structuralKey(of: aggregatedSnapshot) {
                aggregatedSnapshot = next
            }
            let counts = currentTransferCounts()
            if counts != transferCountsByHandle {
                transferCountsByHandle = counts
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Runs in a sampling Task, NOT in body scope — reading `@Observable`
    /// here doesn't subscribe the view.
    private func currentTransferCounts() -> [ConnectionHandle.ID: Int] {
        var counts: [ConnectionHandle.ID: Int] = [:]
        for handle in connections.connections {
            counts[handle.id] = handle.filesVM.transfers.values
                .reduce(into: 0) { acc, state in
                    if state.status == .running { acc += 1 }
                }
        }
        return counts
    }

    private func structuralKey(of rows: [AggregatedTransfer]) -> [String] {
        rows.map { "\($0.id):\($0.state.status)" }
    }

    // MARK: - Connections pane

    private var connectionsPane: some View {
        VStack(spacing: 0) {
            paneHeader(
                title: "Servers",
                systemImage: "server.rack",
                trailing: AnyView(
                    Text("\(connections.connections.count) connections")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                )
            )
            if connections.connections.isEmpty {
                emptyState(
                    systemImage: "network.slash",
                    title: "No active servers",
                    body: "Open a window and connect to a Hotline server to see it here."
                )
            } else {
                Table(connections.connections, selection: $selectedConnection) {
                    TableColumn("Server") { handle in
                        HStack(spacing: Spacing.xsmall.rawValue) {
                            Image(systemName: handle.isLive ? "network" : "network.slash")
                                .foregroundStyle(handle.isLive ? Color.green : Color.red)
                                .symbolRenderingMode(.hierarchical)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(handle.displayName)
                                    .fontWeight(handle.id == selectedConnection ? .medium : .regular)
                                    .foregroundStyle(handle.isLive ? Color.primary : Color.secondary)
                                if case .disconnected(let reason) = handle.phase {
                                    Text(reason?.isEmpty == false ? reason! : "Disconnected")
                                        .font(.caption2)
                                        .foregroundStyle(.red)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        }
                    }
                    TableColumn("Address") { handle in
                        // `grouping(.never)` — SwiftUI's
                        // Text(LocalizedStringKey) re-formats bare int
                        // interpolations through the user's locale,
                        // producing "5.502" in de_DE. Port numbers are
                        // identifiers, not counts; never group.
                        Text(verbatim: "\(handle.settings.address):\(handle.settings.port.formatted(.number.grouping(.never)))")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 140, ideal: 180)
                    TableColumn("Users") { handle in
                        Text(verbatim: "\(handle.userListVM.users.count.formatted(.number.grouping(.never)))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .width(min: 60, ideal: 70, max: 90)
                    TableColumn("Transfers") { handle in
                        Text(verbatim: "\((transferCountsByHandle[handle.id] ?? 0).formatted(.number.grouping(.never)))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .width(min: 80, ideal: 90, max: 110)
                    TableColumn("") { handle in
                        connectionRowActions(handle)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .width(min: 110, ideal: 130, max: 160)
                }
                .contextMenu(forSelectionType: ConnectionHandle.ID.self) { ids in
                    if let id = ids.first ?? selectedConnection,
                       let handle = handle(for: id) {
                        connectionContextMenu(handle)
                    }
                } primaryAction: { ids in
                    if let id = ids.first, let handle = handle(for: id) {
                        if handle.isLive {
                            focus(handle)
                        } else {
                            handle.onReconnect?()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func connectionRowActions(_ handle: ConnectionHandle) -> some View {
        HStack(spacing: 4) {
            if handle.isLive {
                Button {
                    focus(handle)
                } label: {
                    Image(systemName: "macwindow")
                }
                .buttonStyle(.borderless)
                .help("Bring Window to Front")
                Button(role: .destructive) {
                    handle.onDisconnect?()
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .help("Disconnect")
            } else {
                Button {
                    handle.onReconnect?()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Reconnect")
                Button(role: .destructive) {
                    handle.onRemove?()
                    connections.deregister(handle.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove from list")
            }
        }
    }

    @ViewBuilder
    private func connectionContextMenu(_ handle: ConnectionHandle) -> some View {
        if handle.isLive {
            Button("Bring Window to Front") { focus(handle) }
            Button("Disconnect", role: .destructive) { handle.onDisconnect?() }
        } else {
            Button("Reconnect") { handle.onReconnect?() }
            Button("Remove from List", role: .destructive) {
                handle.onRemove?()
                connections.deregister(handle.id)
            }
        }
    }

    // MARK: - Transfers pane

    private var transfersPane: some View {
        VStack(spacing: 0) {
            paneHeader(
                title: "Transfers",
                systemImage: "arrow.up.arrow.down.circle",
                trailing: AnyView(TransferSpeedsFooter(connections: connections))
            )
            if aggregatedSnapshot.isEmpty {
                emptyState(
                    systemImage: "arrow.up.arrow.down.circle",
                    title: "No active transfers",
                    body: "Downloads and uploads from any connected server will appear here."
                )
            } else {
                Table(aggregatedSnapshot, selection: $selectedTransfer) {
                    TableColumn("Server") { row in
                        Text(row.handle.displayName)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 100, ideal: 130, max: 200)

                    // Each cell wraps its live-data read in its own
                    // struct so the `@Observable` subscription scopes
                    // to THAT cell only — calling `liveState(for:)`
                    // straight from the column builder subscribed the
                    // body to `filesVM` and killed row selection.
                    TableColumn("FileItem") { row in
                        TransferFileCell(row: row)
                    }

                    TableColumn("Progress") { row in
                        TransferProgressCell(row: row)
                            // NSProgressIndicator under SwiftUI's
                            // `ProgressView` swallows clicks — disable
                            // hit testing so they fall through to row
                            // selection.
                            .allowsHitTesting(false)
                    }
                    .width(min: 140, ideal: 180)

                    TableColumn("Speed") { row in
                        TransferSpeedCell(row: row)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .width(min: 80, ideal: 90, max: 110)

                    TableColumn("Status") { row in
                        TransferStatusCell(row: row)
                    }
                    .width(min: 90, ideal: 100, max: 120)

                    TableColumn("") { row in
                        TransferActionsCell(
                            row: row,
                            onRemove: { removeTransfer(row) }
                        )
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .width(min: 100, ideal: 110, max: 130)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .contextMenu(forSelectionType: AggregatedTransfer.ID.self) { ids in
                    if let id = ids.first ?? selectedTransfer,
                       let row = aggregatedSnapshot.first(where: { $0.id == id }) {
                        contextMenu(for: row)
                    }
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                newDocument { HeidrunBookmarkDocument() }
            } label: {
                Label("New Connection", systemImage: "plus")
            }
            .help("Open a new connection window")
        }

        ToolbarItemGroup {
            Button {
                clearFinishedEverywhere()
            } label: {
                Label("Clear Finished", systemImage: "checkmark.circle")
            }
            .help("Remove completed and failed transfers from the list")
            .disabled(!hasFinishedRows)

            Button(role: .destructive) {
                cancelAllRunning()
            } label: {
                Label("Cancel All", systemImage: "xmark.circle")
            }
            .help("Cancel every running transfer")
            .disabled(!hasRunningRows)
        }
    }

    // MARK: - Action buttons

    @ViewBuilder
    private func actionButtons(_ row: AggregatedTransfer) -> some View {
        let state = liveState(for: row)
        HStack(spacing: 4) {
            switch state.status {
            case .running:
                Button {
                    Task { await row.handle.filesVM.cancel(state.handle) }
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Cancel")
            case .failed:
                if state.direction == .download, state.sourceFile != nil {
                    Button {
                        Task { await row.handle.filesVM.resume(state) }
                    } label: {
                        Image(systemName: "arrow.clockwise.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Resume")
                }
                Button {
                    removeTransfer(row)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove")
            case .completed:
                if let url = state.destination {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
                }
                Button {
                    removeTransfer(row)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove")
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for row: AggregatedTransfer) -> some View {
        let state = liveState(for: row)
        switch state.status {
        case .running:
            Button("Cancel") {
                Task { await row.handle.filesVM.cancel(state.handle) }
            }
        case .failed:
            if state.direction == .download, state.sourceFile != nil {
                Button("Resume") {
                    Task { await row.handle.filesVM.resume(state) }
                }
            }
            Button("Remove from List") { removeTransfer(row) }
        case .completed:
            if let url = state.destination {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            Button("Remove from List") { removeTransfer(row) }
        }
    }

    // MARK: - Shared chrome

    private func paneHeader(title: LocalizedStringKey, systemImage: String, trailing: AnyView) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.xsmall.rawValue) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .labelStyle(.titleAndIcon)
                Spacer()
                trailing
            }
            .padding(.horizontal, .small)
            .padding(.vertical, .xsmall)
            Divider().opacity(0.5)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    @ViewBuilder
    private func emptyState(systemImage: String, title: String, body: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(body)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func statusBadge(for state: FilesViewModel.TransferState) -> some View {
        switch state.status {
        case .running:
            Label("Running", systemImage: "arrow.down.forward")
                .font(.caption)
                .foregroundStyle(.blue)
                .labelStyle(.titleOnly)
        case .completed:
            Label("Done", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        case .failed(let message):
            Text(message.isEmpty ? String(localized: "Failed") : message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(message)
        }
    }

    // MARK: - Aggregation

    private var aggregated: [AggregatedTransfer] {
        connections.connections.flatMap { handle in
            handle.filesVM.transfers.values.map { state in
                AggregatedTransfer(handle: handle, state: state)
            }
        }
        .sorted { lhs, rhs in
            if lhs.handle.id == rhs.handle.id {
                return lhs.state.handle.transferID < rhs.state.handle.transferID
            }
            return lhs.handle.displayName.localizedCaseInsensitiveCompare(rhs.handle.displayName) == .orderedAscending
        }
    }

    /// Reads the SNAPSHOT's captured status, not live state — toolbar
    /// enable/disable checks must not subscribe the body to `filesVM`.
    private var hasRunningRows: Bool {
        aggregatedSnapshot.contains { $0.state.status == .running }
    }

    private var hasFinishedRows: Bool {
        aggregatedSnapshot.contains { $0.state.status != .running }
    }

    private func activeCount(_ handle: ConnectionHandle) -> Int {
        handle.filesVM.transfers.values.reduce(into: 0) { acc, state in
            if state.status == .running { acc += 1 }
        }
    }

    private func handle(for id: ConnectionHandle.ID) -> ConnectionHandle? {
        connections.connections.first(where: { $0.id == id })
    }

    /// Up-to-the-millisecond state for a snapshot row. Cells use this
    /// (not the captured `row.state`) so the snapshot stays structurally
    /// stable while visuals tick. Falls back to the snapshot state for
    /// the brief window between a VM removal and our next refresh.
    private func liveState(for row: AggregatedTransfer) -> FilesViewModel.TransferState {
        row.handle.filesVM.transfers[row.state.handle.transferID] ?? row.state
    }

    // MARK: - Actions

    private func focus(_ handle: ConnectionHandle) {
        guard let window = handle.window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func removeTransfer(_ row: AggregatedTransfer) {
        row.handle.filesVM.clearFinishedTransfers()
    }

    private func clearFinishedEverywhere() {
        for handle in connections.connections {
            handle.filesVM.clearFinishedTransfers()
        }
    }

    private func cancelAllRunning() {
        for handle in connections.connections {
            for state in handle.filesVM.transfers.values where state.status == .running {
                Task { await handle.filesVM.cancel(state.handle) }
            }
        }
    }

    private func progressText(_ state: FilesViewModel.TransferState) -> String {
        let done = ByteCountFormatter.string(fromByteCount: Int64(state.bytesWritten), countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: Int64(state.totalSize), countStyle: .file)
        return "\(done) / \(total)"
    }
}
