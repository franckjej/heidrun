import SwiftUI
import AppKit
import HeidrunCore
import HeidrunUI
import CommonTools

// MARK: - File Info sheet

/// Modal sheet behind the toolbar / context-menu "Get Info…" action.
/// Reads file metadata from the server (`fetchInfo`), surfaces it in
/// a labelled card, and lets the user edit + persist a comment via
/// `saveComment` (which routes through `FilesViewModel.setComment`).
///
/// Lives in its own file so `FilesView.swift` stays under SwiftLint's
/// file-length cap; the only external caller is the `.sheet(item:)`
/// modifier in `FilesView.body`.
struct FileInfoSheet: View {
    let entry: RemoteFile
    let path: RemotePath
    let fetchInfo: @MainActor () async throws -> RemoteFileInfo
    let saveComment: @MainActor (String) async -> Void
    let onClose: () -> Void

    @State private var info: RemoteFileInfo?
    @State private var loadError: String?
    @State private var isLoading: Bool = true
    @State private var commentDraft: String = ""
    @State private var originalComment: String = ""
    @State private var isSavingComment: Bool = false
    @State private var showSavedBadge: Bool = false

    private var isCommentDirty: Bool { commentDraft != originalComment }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium.rawValue) {
            header
            metadataCard
            commentEditor
            Spacer(minLength: 0)
            footer
        }
        .padding(.medium)
        .frame(minWidth: 460, minHeight: 460)
        .closeOnCmdW(onClose)
        .task { await load() }
    }

    // MARK: - Sections

    /// Title bar: large file-type-aware glyph + name + parent path.
    /// The icon picks a representative SF Symbol based on the file
    /// extension (or `folder`/`doc` as fall-throughs) so a quick
    /// glance at the sheet conveys "what kind of thing am I looking
    /// at" without reading the type code below.
    private var header: some View {
        HStack(alignment: .center, spacing: Spacing.medium.rawValue) {
            Image(systemName: iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundStyle(iconTint)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.title3.weight(.semibold))
                    .textSelection(.enabled)
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(path.isRoot ? "/" : path.displayPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Card holding the file-system metadata grid: size, type, creator,
    /// created / modified dates. Kept inside a styled rounded card so
    /// it reads as one chunk rather than five loose key/value rows.
    @ViewBuilder
    private var metadataCard: some View {
        GroupBox {
            if isLoading {
                HStack(spacing: Spacing.xsmall.rawValue) {
                    ProgressView().controlSize(.small)
                    Text("Loading…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.xxsmall)
            } else if let info {
                HStack(spacing: 0) {
                    Grid(
                        alignment: .leading,
                        horizontalSpacing: Spacing.medium.rawValue,
                        verticalSpacing: Spacing.xsmall.rawValue
                    ) {
                        row("Size", sizeLabel(info.dataForkSize))
                        if info.resourceForkSize > 0 {
                            row("Resource Fork", sizeLabel(info.resourceForkSize))
                        }
                        row("Type", info.file.type.stringValue, monospaced: true)
                        row("Creator", info.file.creator.stringValue, monospaced: true)
                        if let created = info.creationDate {
                            row("Created", Self.dateFormatter.string(from: created))
                        }
                        if let modified = info.modificationDate {
                            row("Modified", Self.dateFormatter.string(from: modified))
                        }
                    }
                    .font(.callout)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.xxsmall)
            } else if let loadError {
                Label(loadError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.xxsmall)
            }
        } label: {
            Label("File", systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            if let info {
                Button("Copy File Info") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        copyableInfoBlock(info: info),
                        forType: .string
                    )
                }
            }
        }
    }

    /// Multi-line plain-text dump of the whole sheet — name + path,
    /// metadata grid, then the comment if any. Tab-separated key/value
    /// pairs so Numbers / spreadsheets can absorb it too.
    private func copyableInfoBlock(info: RemoteFileInfo) -> String {
        var lines: [String] = []
        lines.append(entry.name)
        lines.append(path.isRoot ? "/" : path.displayPath)
        lines.append("")
        lines.append("Size:\t\(sizeLabel(info.dataForkSize))")
        if info.resourceForkSize > 0 {
            lines.append("Resource Fork:\t\(sizeLabel(info.resourceForkSize))")
        }
        lines.append("Type:\t\(info.file.type.stringValue)")
        lines.append("Creator:\t\(info.file.creator.stringValue)")
        if let created = info.creationDate {
            lines.append("Created:\t\(Self.dateFormatter.string(from: created))")
        }
        if let modified = info.modificationDate {
            lines.append("Modified:\t\(Self.dateFormatter.string(from: modified))")
        }
        let comment = (info.comment ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !comment.isEmpty {
            lines.append("")
            lines.append("Comment:")
            lines.append(comment)
        }
        return lines.joined(separator: "\n")
    }

    /// Comment editor. Sits below the metadata card with the same
    /// "section header + rounded card" rhythm. Server persists via
    /// setFileInfo (207) through FilesViewModel.setComment, plumbed
    /// in through `saveComment`.
    @ViewBuilder
    private var commentEditor: some View {
        if info != nil {
            VStack(alignment: .leading, spacing: Spacing.xxsmall.rawValue) {
                HStack(spacing: Spacing.xxsmall.rawValue) {
                    Label("Comment", systemImage: "text.bubble")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isCommentDirty {
                        Text("Unsaved")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else if showSavedBadge {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                    }
                }
                TextEditor(text: $commentDraft)
                    .font(.callout)
                    .frame(minHeight: 90, maxHeight: 160)
                    .scrollContentBackground(.hidden)
                    .padding(.xxsmall)
                    .background(
                        RoundedRectangle(cornerRadius: .cornerHigh, style: .continuous)
                            .fill(.background.secondary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: .cornerHigh, style: .continuous)
                            .strokeBorder(
                                isCommentDirty ? AnyShapeStyle(Color.accentColor.opacity(0.6))
                                               : AnyShapeStyle(.separator),
                                lineWidth: 0.5
                            )
                    )
                    .disabled(isSavingComment)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: Spacing.xsmall.rawValue) {
            Spacer()
            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
            Button {
                Task { await commit() }
            } label: {
                if isSavingComment {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Save")
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(info == nil || !isCommentDirty || isSavingComment)
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func row(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Group {
                if monospaced {
                    Text(value).font(.callout.monospaced())
                } else {
                    Text(value)
                }
            }
            .textSelection(.enabled)
        }
    }

    /// "127 KB (130,048 bytes)" — pretty unit on the left, exact count
    /// in parens so admins triaging odd uploads can still see the raw
    /// byte width.
    private func sizeLabel(_ bytes: UInt32) -> String {
        let raw = Int64(bytes)
        let pretty = ByteCountFormatter.string(fromByteCount: raw, countStyle: .file)
        let exact = Self.exactFormatter.string(from: NSNumber(value: raw)) ?? "\(raw)"
        return "\(pretty) (\(exact) bytes)"
    }

    /// SF Symbol that vaguely matches the file extension. Folder check
    /// short-circuits to `folder.fill`; otherwise the extension drives
    /// a coarse category mapping. Falls back to `doc` for anything
    /// unrecognised — same default the legacy list view uses.
    private var iconName: String {
        if entry.isFolder { return "folder.fill" }
        let extn = (entry.name as NSString).pathExtension.lowercased()
        switch extn {
        case "txt", "md", "markdown", "rtf", "log":
            return "doc.text.fill"
        case "html", "htm", "css", "js", "swift", "c", "cpp", "h", "hpp",
             "m", "mm", "py", "rb", "sh", "go", "rs", "java", "kt", "kts",
             "ts", "tsx", "jsx":
            return "chevron.left.forwardslash.chevron.right"
        case "json", "xml", "yaml", "yml", "toml", "plist", "conf", "ini", "cfg":
            return "doc.badge.gearshape.fill"
        case "jpg", "jpeg", "png", "gif", "tiff", "bmp", "heic":
            return "photo.fill"
        case "mp3", "wav", "aiff", "flac", "m4a", "ogg":
            return "music.note"
        case "mp4", "mov", "avi", "mkv", "m4v":
            return "play.rectangle.fill"
        case "pdf":
            return "doc.richtext.fill"
        case "zip", "tar", "gz", "bz2", "7z", "rar", "sit", "sitx":
            return "archivebox.fill"
        case "dmg", "iso":
            return "opticaldiscdrive.fill"
        default:
            return "doc.fill"
        }
    }

    private var iconTint: Color {
        entry.isFolder ? .accentColor : .secondary
    }

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await fetchInfo()
            info = fetched
            let initial = fetched.comment ?? ""
            commentDraft = initial
            originalComment = initial
        } catch {
            loadError = String(describing: error)
        }
    }

    @MainActor
    private func commit() async {
        guard isCommentDirty else { return }
        isSavingComment = true
        defer { isSavingComment = false }
        let pending = commentDraft
        await saveComment(pending)
        // Re-fetch so the sheet reflects what the server actually
        // stored — defensive against trimming / encoding round-trips
        // and keeps the dirty marker honest on subsequent edits.
        if let refreshed = try? await fetchInfo() {
            info = refreshed
            let stored = refreshed.comment ?? ""
            commentDraft = stored
            originalComment = stored
        } else {
            originalComment = pending
        }
        showSavedBadge = true
        try? await Task.sleep(for: .seconds(2))
        showSavedBadge = false
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let exactFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}
