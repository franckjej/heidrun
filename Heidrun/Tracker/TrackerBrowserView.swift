import SwiftUI
import CommonTools
import HeidrunCore

/// Shared tracker browser body used by both the standalone window
/// (`TrackerWindowView`) and the connect-sheet (`TrackerBrowser`).
/// Behavior that differs between the two lives behind `mode`: the
/// bottom-bar Cancel button and what a pick does.
@MainActor
struct TrackerBrowserView: View {
    let mode: TrackerBrowserMode

    @State private var hostsStore = TrackerHostsRegistry.shared
    @State private var viewModel = TrackerBrowserViewModel(
        hosts: TrackerHostsRegistry.shared.hosts
    )
    @State private var selection: MergedTrackerServer.ID?
    @State private var showingHostsEditor = false
    @State private var refreshTask: Task<Void, Never>?
    @SceneStorage("Tracker.sortOrder") private var sortOrderRaw: String = "users.desc"
    @State private var sortOrder: [KeyPathComparator<MergedTrackerServer>] = [
        KeyPathComparator(\MergedTrackerServer.server.users, order: .reverse)
    ]
    @Environment(\.newDocument) private var newDocument
    @AppStorage(AppStorageKeys.defaultNickname) private var defaultNickname: String = NSFullUserName()
    @AppStorage(AppStorageKeys.defaultIconID) private var defaultIconID: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            toolbarStrip
            Divider()
            if !viewModel.failedHosts.isEmpty {
                errorStrip
                Divider()
            }
            content
            Divider()
            bottomBar
        }
        .frame(minWidth: 720, minHeight: 480)
        .task {
            startRefresh()
            await refreshTask?.value
        }
        .onDisappear { refreshTask?.cancel() }
        .onChange(of: hostsStore.hosts) { _, newHosts in
            viewModel.hosts = newHosts
        }
        .onChange(of: sortOrder) { _, newOrder in
            sortOrderRaw = encode(newOrder)
        }
    }

    // MARK: - Toolbar (filter + count + edit + refresh)

    private var toolbarStrip: some View {
        HStack(spacing: Spacing.xsmall.rawValue) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter", text: $viewModel.filter)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
            Text(serverCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if viewModel.timedOutCount > 0 {
                Label("\(viewModel.timedOutCount) timed out", systemImage: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .labelStyle(.titleAndIcon)
            }

            Spacer()

            Button {
                showingHostsEditor.toggle()
            } label: {
                Label("Trackers…", systemImage: "antenna.radiowaves.left.and.right")
            }
            .buttonStyle(.bordered)
            .popover(isPresented: $showingHostsEditor) {
                TrackerHostsEditor()
            }

            if viewModel.state == .loading {
                Button(role: .cancel) {
                    cancelRefresh()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            } else {
                Button {
                    startRefresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, .small)
        .padding(.vertical, .xsmall)
        .background(.bar)
    }

    /// "N servers" when unfiltered; "filtered / total" when a filter is
    /// active.
    private var serverCountLabel: String {
        let total = viewModel.servers.count
        let filtered = viewModel.filteredServers.count
        if viewModel.filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return total == 1 ? "1 server" : "\(total) servers"
        }
        return "\(filtered) / \(total)"
    }

    // MARK: - Error strip

    private var errorStrip: some View {
        VStack(alignment: .leading, spacing: Spacing.xxsmall.rawValue) {
            ForEach(viewModel.failedHosts, id: \.self) { failed in
                let isTimeout = failed.kind == .timeout
                HStack {
                    Image(systemName: isTimeout ? "clock.badge.exclamationmark" : "exclamationmark.triangle")
                        .foregroundStyle(isTimeout ? .red : .orange)
                    Text("\(failed.host.name) (\(failed.host.host)) — \(failed.message)")
                        .font(.caption)
                        .foregroundStyle(isTimeout ? .red : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, .small)
        .padding(.vertical, .xsmall)
        .background(.bar.opacity(0.5))
    }

    // MARK: - Content (table / loading / empty / failed)

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            ProgressView("Loading server list…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading where viewModel.servers.isEmpty:
            ProgressView("Loading server list…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded where viewModel.servers.isEmpty:
            VStack {
                Spacer()
                ContentUnavailableView(
                    "No Servers",
                    systemImage: "server.rack",
                    description: Text("No servers reported across your \(viewModel.hosts.filter(\.enabled).count) enabled trackers.")
                )
                .fixedSize()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message) where viewModel.servers.isEmpty:
            VStack(spacing: Spacing.small.rawValue) {
                Label("Failed to Load", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, .large)
                Button("Retry") {
                    startRefresh()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded, .loading, .failed:
            serverTable
        }
    }

    /// Drag a tracker server out to Finder as a one-server
    /// `.heidrunbookmarks` file (synchronous; reliable in a Table).
    private func trackerDragProvider(for server: TrackerServer) -> NSItemProvider {
        BookmarkExport(bookmarks: [BookmarkExport.bookmark(from: server)]).makeItemProvider()
    }

    private var serverTable: some View {
        Table(
            viewModel.filteredServers.sorted(using: sortOrder),
            selection: $selection,
            sortOrder: $sortOrder
        ) {
            TableColumn("Name", value: \MergedTrackerServer.server.name) { row in
                Text(row.server.name)
                    .onDrag { trackerDragProvider(for: row.server) }
            }
            .width(min: 140, ideal: 180)
            TableColumn("Description", value: \MergedTrackerServer.server.description)
                .width(min: 140, ideal: 240)
            TableColumn("Users", value: \MergedTrackerServer.server.users) { server in
                Text(verbatim: "\(server.server.users.formatted(.number.grouping(.never)))")
                    .monospacedDigit()
            }
            .width(min: 48, ideal: 56, max: 72)
            TableColumn("Address", value: \MergedTrackerServer.server.address) { server in
                Text(verbatim: "\(server.server.address):\(server.server.port.formatted(.number.grouping(.never)))")
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 140, ideal: 170)
            if viewModel.hosts.filter(\.enabled).count >= 2 {
                TableColumn("Source") { server in
                    Text(server.sources.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 120)
            }
        }
        .contextMenu(forSelectionType: MergedTrackerServer.ID.self) { _ in
            EmptyView()
        } primaryAction: { ids in
            guard let pickedID = ids.first,
                  let row = viewModel.servers.first(where: { $0.id == pickedID })
            else { return }
            deliverPick(row.server)
        }
    }

    // MARK: - Bottom bar (Cancel only in sheet mode)

    private var bottomBar: some View {
        HStack {
            if case .sheet(_, let onCancel) = mode {
                Button("Cancel", role: .cancel) { onCancel() }
            }
            Spacer()
            Button("Use Server") { handleUseServer() }
                .disabled(selection == nil)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, .small)
        .padding(.vertical, .xsmall)
        .background(.bar)
    }

    // MARK: - Refresh lifecycle

    /// Start a refresh in a cancellable task so the Cancel button (and view
    /// teardown) can abort an in-flight fetch. Cancels any prior refresh
    /// first so we never run two concurrently.
    private func startRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            viewModel.hosts = hostsStore.hosts
            await viewModel.refresh()
        }
    }

    private func cancelRefresh() {
        refreshTask?.cancel()
    }

    // MARK: - Pick dispatch

    private func handleUseServer() {
        guard let id = selection,
              let row = viewModel.servers.first(where: { $0.id == id })
        else { return }
        deliverPick(row.server)
    }

    private func deliverPick(_ server: TrackerServer) {
        switch mode {
        case .window:
            let resolvedLogin = TrackerPickResolver.resolveLogin(
                address: server.address,
                port: server.port
            )
            let settings = ConnectionSettings(
                name: server.name,
                address: server.address,
                port: server.port,
                nickname: defaultNickname,
                login: resolvedLogin,
                icon: UInt16(clamping: defaultIconID)
            )
            newDocument { HeidrunBookmarkDocument.seeded(with: settings) }
        case .sheet(let onPick, _):
            onPick(server)
        }
    }

    // MARK: - @SceneStorage encoding for sortOrder

    private func encode(_ order: [KeyPathComparator<MergedTrackerServer>]) -> String {
        guard let first = order.first else { return "users.desc" }
        let direction = first.order == .reverse ? "desc" : "asc"
        if first.keyPath == \MergedTrackerServer.server.users {
            return "users.\(direction)"
        }
        if first.keyPath == \MergedTrackerServer.server.name {
            return "name.\(direction)"
        }
        if first.keyPath == \MergedTrackerServer.server.description {
            return "description.\(direction)"
        }
        if first.keyPath == \MergedTrackerServer.server.address {
            return "address.\(direction)"
        }
        return "users.desc"
    }
}
