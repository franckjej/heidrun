import SwiftUI
import AppKit
import HeidrunCore
import HeidrunUI
import CommonTools

/// Two-pane file browser: header (ActionButtons), breadcrumb, selectable
/// list, transfer drawer.
public struct FilesView: View {
    @State private var viewModel: FilesViewModel
    @State private var selection: Set<RemoteFile.ID> = []
    @State private var renameTarget: RemoteFile?
    @State private var renameDraft: String = ""
    @State private var infoTarget: RemoteFile?
    @State private var creatingFolder: Bool = false
    @State private var newFolderDraft: String = ""
    @State private var conflictEntry: RemoteFile?
    @State private var deleteTargets: [RemoteFile] = []
    @State private var downloadRequest: DownloadRequest?
    @State private var showingTaskManager: Bool = false
    @State private var previewWindowController = FilePreviewWindowController()
    @State private var sortKey: FileSortKey = .name
    @State private var sortAscending: Bool = true

    /// Stable identifier for the connection — used to scope per-server
    /// preferences like the Quick Look panel's autosaved frame. `nil`
    /// disables per-server scoping and falls back to a global key.
    private let serverIdentifier: String?

    public init(viewModel: FilesViewModel, serverIdentifier: String? = nil) {
        self._viewModel = State(initialValue: viewModel)
        self.serverIdentifier = serverIdentifier
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            breadcrumb
            Divider()
            fileList
            if !viewModel.transfers.isEmpty {
                Divider()
                transferDrawer
            }
            // Errors surface through the scene-root ErrorPresenter.
        }
        .padding(.bottom, .xlarge)
        .frame(alignment: .topLeading)
        .task { await viewModel.refresh() }
        .onChange(of: viewModel.files) { _, newValue in
            // Drop ids that no longer exist in the listing.
            selection.formIntersection(Set(newValue.map(\.id)))
        }
        .sheet(item: $renameTarget) { target in renameSheet(target) }
        .sheet(item: $infoTarget) { target in infoSheet(target) }
        .sheet(isPresented: $creatingFolder) { newFolderSheet }
        .sheet(isPresented: $showingTaskManager) {
            TransferTaskManagerSheet(
                transfers: sortedTransfers,
                onClear: { viewModel.clearFinishedTransfers() },
                onCancel: { handle in Task { await viewModel.cancel(handle) } },
                onClose: { showingTaskManager = false }
            )
        }
        .alert(
            "Already in your download folder",
            isPresented: conflictBinding,
            presenting: conflictEntry
        ) { entry in
            Button("Replace") {
                Task { await viewModel.download(entry, mode: .fresh) }
            }
            Button("Resume") {
                Task { await viewModel.download(entry, mode: .resume) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text(
                "“\(entry.name)” already exists locally. " +
                "Replace it with a fresh copy, resume the partial download, or cancel?"
            )
        }
        .alert(deleteAlertTitle, isPresented: deleteBinding) {
            Button("Delete", role: .destructive) {
                let targets = deleteTargets
                deleteTargets = []
                selection = []
                Task { await viewModel.deleteAll(targets) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteAlertMessage)
        }
        .alert(
            "Some files already exist",
            isPresented: downloadRequestBinding,
            presenting: downloadRequest
        ) { request in
            Button("Replace All") {
                for file in request.files {
                    Task { await viewModel.download(file, mode: .fresh) }
                }
            }
            Button("Resume All") {
                let conflictIDs = Set(request.conflicts.map(\.id))
                for file in request.files {
                    let mode: FilesViewModel.DownloadMode =
                        conflictIDs.contains(file.id) ? .resume : .fresh
                    Task { await viewModel.download(file, mode: mode) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { request in
            Text(
                "\(request.conflicts.count) of \(request.files.count) selected files " +
                "already exist in your download folder. Replace them with fresh copies, " +
                "resume the partial downloads, or cancel?"
            )
        }
        .alert(
            uploadConflictTitle,
            isPresented: uploadConflictBinding,
            presenting: viewModel.pendingUploadConflict
        ) { pending in
            // Capture `pending` synchronously here — SwiftUI's auto
            // dismissal fires the binding's set (→ cancelPendingUpload)
            // before the dispatched Task body runs, so reading
            // viewModel.pendingUploadConflict inside the Task would
            // always be nil.
            Button("Replace") {
                Task { await viewModel.replacePendingUpload(pending) }
            }
            Button("Resume") {
                Task { await viewModel.resumePendingUpload(pending) }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelPendingUpload()
            }
        } message: { pending in
            if pending.replaceAttemptFailed {
                Text(
                    "We removed “\(pending.targetName)” but the server " +
                    "still reports it. The server may not have applied " +
                    "the delete yet, or it may have rejected it silently. " +
                    "Try Replace again, Resume to append, or Cancel."
                )
            } else {
                Text(
                    "“\(pending.targetName)” already exists on the server. " +
                    "Replace deletes the server copy and uploads a fresh one; " +
                    "Resume appends to the existing file (useful after an " +
                    "interrupted upload)."
                )
            }
        }
    }

    private var conflictBinding: Binding<Bool> {
        Binding(
            get: { conflictEntry != nil },
            set: { if !$0 { conflictEntry = nil } }
        )
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { !deleteTargets.isEmpty },
            set: { if !$0 { deleteTargets = [] } }
        )
    }

    private var downloadRequestBinding: Binding<Bool> {
        Binding(
            get: { downloadRequest != nil },
            set: { if !$0 { downloadRequest = nil } }
        )
    }

    private var uploadConflictTitle: LocalizedStringKey {
        viewModel.pendingUploadConflict?.replaceAttemptFailed == true
            ? "Couldn't replace the file"
            : "Already on the server"
    }

    private var uploadConflictBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingUploadConflict != nil },
            set: { if !$0 { viewModel.cancelPendingUpload() } }
        )
    }

    private var deleteAlertTitle: LocalizedStringKey {
        deleteTargets.count == 1 ? "Delete this item?" : "Delete \(deleteTargets.count) items?"
    }

    private var deleteAlertMessage: String {
        if deleteTargets.count == 1, let entry = deleteTargets.first {
            return entry.isFolder
                ? String(localized: "“\(entry.name)” and everything inside it will be removed from the server. This can't be undone.", bundle: .module)
                : String(localized: "“\(entry.name)” will be removed from the server. This can't be undone.", bundle: .module)
        }
        let count = deleteTargets.count
        return deleteTargets.contains(where: \.isFolder)
            ? String(localized: "\(count) items (including folders and their contents) will be removed from the server. This can't be undone.", bundle: .module)
            : String(localized: "\(count) items will be removed from the server. This can't be undone.", bundle: .module)
    }

    /// Confirms when a local copy already exists; otherwise downloads fresh.
    private func requestDownload(_ entry: RemoteFile) {
        if viewModel.localFileExists(for: entry) {
            conflictEntry = entry
        } else {
            Task { await viewModel.download(entry, mode: .fresh) }
        }
    }

    /// `conflicts` is the subset of `files` already present locally.
    private struct DownloadRequest: Identifiable {
        let id = UUID()
        let files: [RemoteFile]
        let conflicts: [RemoteFile]
    }

    /// Multiple-file path: one combined Replace-all / Resume-all prompt
    /// when anything conflicts.
    private func requestDownloadMany(_ files: [RemoteFile]) {
        guard !files.isEmpty else { return }
        if files.count == 1, let only = files.first {
            requestDownload(only)
            return
        }
        let conflicts = files.filter { viewModel.localFileExists(for: $0) }
        if conflicts.isEmpty {
            for file in files { Task { await viewModel.download(file, mode: .fresh) } }
        } else {
            downloadRequest = DownloadRequest(files: files, conflicts: conflicts)
        }
    }

    /// Whether the current selection can be deleted given the account's
    /// privileges — files need `deleteFiles`, folders need `deleteFolders`.
    /// Fail-open via `permits` (a server that doesn't advertise privileges
    /// keeps Delete enabled). UI hint only; the server still enforces.
    private var canDeleteSelection: Bool {
        let entries = selectedEntries
        let hasFile = entries.contains { !$0.isFolder }
        let hasFolder = entries.contains { $0.isFolder }
        return (!hasFile || viewModel.permits(.deleteFiles))
            && (!hasFolder || viewModel.permits(.deleteFolders))
    }

    // MARK: - Header

    /// Same vertical metrics as the chat / user-list headers so they
    /// line up across the window.
    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.xxsmall.rawValue) {
            ActionButton(
                title: "Up",
                systemImage: "chevron.up",
                isEnabled: !viewModel.currentPath.isRoot,
                size: .small,
                fontWeight: .light
            ) {
                Task { await viewModel.navigateUp() }
            }

            Divider().frame(height: 16)

            ActionButton(
                title: "Download",
                systemImage: "arrow.down.circle",
                isEnabled: !selectedFiles.isEmpty && viewModel.permits(.downloadFiles),
                size: .small,
                fontWeight: .light
            ) {
                requestDownloadMany(selectedFiles)
            }

            ActionButton(
                title: "Upload…",
                systemImage: "arrow.up.circle",
                isEnabled: viewModel.permits(.uploadFiles),
                size: .small,
                fontWeight: .light
            ) {
                pickAndUpload()
            }

            ActionButton(
                title: "New Folder…",
                systemImage: "folder.badge.plus",
                isEnabled: viewModel.permits(.createFolders),
                size: .small,
                fontWeight: .light
            ) {
                newFolderDraft = ""
                creatingFolder = true
            }

            ActionButton(
                title: "Quick Look",
                systemImage: "eye",
                isEnabled: previewableSelection != nil,
                size: .small,
                fontWeight: .light
            ) {
                if let entry = previewableSelection { presentPreview(for: entry) }
            }

            ActionButton(
                title: "Get Info",
                systemImage: "info.circle",
                isEnabled: singleSelection != nil,
                size: .small,
                fontWeight: .light
            ) {
                infoTarget = singleSelection
            }

            ActionButton(
                title: "Refresh",
                systemImage: "arrow.clockwise",
                isEnabled: !viewModel.isLoading,
                size: .small,
                fontWeight: .light
            ) {
                Task { await viewModel.refresh() }
            }

            Spacer(minLength: Spacing.xxsmall.rawValue)

            ActionButton(
                title: "Delete",
                systemImage: "xmark.circle",
                isEnabled: !selectedEntries.isEmpty && canDeleteSelection,
                role: .destructive,
                size: .small,
                fontWeight: .light
            ) {
                deleteTargets = selectedEntries
            }
        }
        .filledHeaderBox()
        .padding(.horizontal, .xsmall)
    }

    private var breadcrumb: some View {
        HStack(spacing: Spacing.xxsmall.rawValue) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(viewModel.currentPath.isRoot ? "/" : viewModel.currentPath.displayPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, .small)
        .padding(.vertical, .xxsmall)
    }

    /// Every selected entry, in listing order (files and folders).
    private var selectedEntries: [RemoteFile] {
        viewModel.files.filter { selection.contains($0.id) }
    }

    /// Selected non-folder entries — the download targets. Folders are
    /// skipped (parity with drag-out and the original single download).
    private var selectedFiles: [RemoteFile] {
        selectedEntries.filter { !$0.isFolder }
    }

    /// The one selected entry when the selection is a single item, else
    /// `nil`. Drives the single-item-only actions (Get Info / Quick Look).
    private var singleSelection: RemoteFile? {
        guard selection.count == 1 else { return nil }
        return selectedEntries.first
    }

    /// The single selection if it's something the preview panel can show.
    /// Drives the enabled state of the Quick Look button.
    private var previewableSelection: RemoteFile? {
        guard let entry = singleSelection, !entry.isFolder,
              FilesViewModel.isPreviewable(entry) else { return nil }
        return entry
    }

    /// Kick off an in-memory preview for `entry` and bring the floating
    /// panel forward. Always pre-opens the panel so the user sees the
    /// loading state while the bytes drain in.
    private func presentPreview(for entry: RemoteFile) {
        Task { await viewModel.previewFile(entry) }
        let hostWindow = NSApp.keyWindow ?? NSApp.mainWindow
        previewWindowController.show(
            for: viewModel,
            near: hostWindow,
            serverIdentifier: serverIdentifier
        )
    }

    // MARK: - List

    private var sortedFiles: [RemoteFile] {
        let sorted: [RemoteFile]
        switch sortKey {
        case .name:
            sorted = viewModel.files.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .size:
            sorted = viewModel.files.sorted { $0.size < $1.size }
        }
        return sortAscending ? sorted : sorted.reversed()
    }

    private var fileList: some View {
        FileTableView(
            files: sortedFiles,
            selection: $selection,
            sortAscending: $sortAscending,
            sortKey: $sortKey,
            actions: fileRowActions,
            writeFile: { [path = viewModel.currentPath] entry, url in
                try await viewModel.downloadFile(entry, at: path, to: url)
            },
            permits: { viewModel.permits($0) }
        )
    }

    /// Bridges the AppKit list's row interactions back to this view's
    /// existing actions + sheet/alert state.
    private var fileRowActions: FileRowActions {
        FileRowActions(
            activate: { activate($0) },
            download: { requestDownload($0) },
            quickLook: { presentPreview(for: $0) },
            isPreviewable: { FilesViewModel.isPreviewable($0) },
            navigateInto: { entry in Task { await viewModel.navigateInto(entry) } },
            getInfo: { infoTarget = $0 },
            rename: { entry in
                renameDraft = entry.name
                renameTarget = entry
            },
            delete: { entry in deleteTargets = [entry] },
            downloadMany: { entries in requestDownloadMany(entries.filter { !$0.isFolder }) },
            deleteMany: { entries in deleteTargets = entries },
            uploadHere: { pickAndUpload() },
            newFolder: {
                newFolderDraft = ""
                creatingFolder = true
            },
            refresh: { Task { await viewModel.refresh() } },
            secondaryLabel: { secondaryLabel(for: $0) },
            dropURLs: { urls in
                Task {
                    for url in urls {
                        if Self.isDirectory(url) {
                            await viewModel.uploadFolder(folderURL: url)
                        } else {
                            await viewModel.upload(fileURL: url)
                        }
                    }
                }
            }
        )
    }

    private func activate(_ entry: RemoteFile) {
        if entry.isFolder {
            Task { await viewModel.navigateInto(entry) }
        } else {
            requestDownload(entry)
        }
    }

    private func secondaryLabel(for entry: RemoteFile) -> String {
        if entry.isFolder {
            return String(localized: "\(Int(entry.itemCount)) items", bundle: .module)
        }
        return ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file)
    }

    // MARK: - Transfer drawer

    /// Compact drawer: at most one upload + one download "primary" tile
    /// (newest running, falling back to newest finished). The full
    /// history lives behind Task Manager.
    private var transferDrawer: some View {
        VStack(alignment: .leading, spacing: Spacing.xsmall.rawValue) {
            HStack(spacing: Spacing.xsmall.rawValue) {
                Label("Transfers", systemImage: "arrow.up.arrow.down.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if hasFinishedTransfers {
                    Button("Clear") {
                        viewModel.clearFinishedTransfers()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
                }
                Button {
                    showingTaskManager = true
                } label: {
                    Label(
                        viewModel.transfers.count > visibleTransfers.count
                            ? "Task Manager (\(viewModel.transfers.count))"
                            : "Task Manager",
                        systemImage: "list.bullet.rectangle"
                    )
                    .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
            .padding(.horizontal, .xsmall)

            ForEach(visibleTransfers, id: \.id) { state in
                TransferTile(state: state) {
                    Task { await viewModel.cancel(state.handle) }
                }
            }
        }
        .padding(.horizontal, .xsmall)
        .padding(.vertical, .xxsmall)
    }

    private var sortedTransfers: [FilesViewModel.TransferState] {
        viewModel.transfers.values.sorted { $0.handle.transferID > $1.handle.transferID }
    }

    /// Download first when both directions exist (mirrors the
    /// arrow.down.arrow.up reading direction).
    private var visibleTransfers: [FilesViewModel.TransferState] {
        [
            primaryTransfer(direction: .download),
            primaryTransfer(direction: .upload)
        ].compactMap { $0 }
    }

    private var hasFinishedTransfers: Bool {
        viewModel.transfers.values.contains(where: { $0.status != .running })
    }

    /// Newest = highest transferID (actor mints monotonically).
    private func primaryTransfer(direction: FilesViewModel.TransferDirection) -> FilesViewModel.TransferState? {
        let candidates = viewModel.transfers.values.filter { $0.direction == direction }
        let running = candidates.filter { $0.status == .running }
        if let mostRecentRunning = running.max(by: { $0.handle.transferID < $1.handle.transferID }) {
            return mostRecentRunning
        }
        return candidates.max(by: { $0.handle.transferID < $1.handle.transferID })
    }

    // MARK: - Picker

    private func pickAndUpload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Upload"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task {
            for url in urls {
                if Self.isDirectory(url) {
                    await viewModel.uploadFolder(folderURL: url)
                } else {
                    await viewModel.upload(fileURL: url)
                }
            }
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    // MARK: - Sheets

    @ViewBuilder
    private func renameSheet(_ target: RemoteFile) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small.rawValue) {
            Text("Rename \(target.name)")
                .font(.headline)
            TextField("New name", text: $renameDraft)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 280)
            HStack {
                Spacer()
                Button("Cancel") { renameTarget = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    let new = renameDraft
                    let entry = target
                    renameTarget = nil
                    Task { await viewModel.rename(entry, to: new) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(renameDraft.isEmpty || renameDraft == target.name)
            }
        }
        .padding(.small)
        .frame(minWidth: 320)
    }

    @ViewBuilder
    private var newFolderSheet: some View {
        VStack(alignment: .leading, spacing: Spacing.small.rawValue) {
            Text("New Folder in \(viewModel.currentPath.isRoot ? "/" : viewModel.currentPath.displayPath)")
                .font(.headline)
            TextField("Folder name", text: $newFolderDraft)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 280)
            HStack {
                Spacer()
                Button("Cancel") { creatingFolder = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    let name = newFolderDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    creatingFolder = false
                    Task { await viewModel.createFolder(named: name) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newFolderDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.small)
        .frame(minWidth: 320)
    }

    @ViewBuilder
    private func infoSheet(_ target: RemoteFile) -> some View {
        FileInfoSheet(
            entry: target,
            path: viewModel.currentPath,
            fetchInfo: { try await viewModel.fetchFileInfo(target) },
            saveComment: { newComment in
                await viewModel.setComment(on: target, newComment)
            },
            onClose: { infoTarget = nil }
        )
    }
}
