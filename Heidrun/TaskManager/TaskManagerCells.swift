import SwiftUI
import AppKit
import HeidrunCore
import HeidrunFiles
import CommonTools

/// Per-cell View structs for the transfers table. Each owns its own
/// body, so reading `row.handle.filesVM.transfers[...]` from inside
/// subscribes only this cell to the @Observable invalidation —
/// instead of leaking the subscription up into `TaskManagerView`'s
/// body, which would rebuild the whole Table on every byte and clear
/// the user's row selection. The `liveState` helper falls back to the
/// snapshot's captured state during the brief window after a transfer
/// is removed from `filesVM` but before the refresh tick drops it
/// from `aggregatedSnapshot`.

@MainActor
private func cellLiveState(_ row: AggregatedTransfer) -> FilesViewModel.TransferState {
    row.handle.filesVM.transfers[row.state.handle.transferID] ?? row.state
}

private func cellProgressText(_ state: FilesViewModel.TransferState) -> String {
    let done = ByteCountFormatter.string(fromByteCount: Int64(state.bytesWritten), countStyle: .file)
    let total = ByteCountFormatter.string(fromByteCount: Int64(state.totalSize), countStyle: .file)
    return "\(done) / \(total)"
}

private func cellFormatSpeed(_ bytesPerSec: Double) -> String {
    guard bytesPerSec > 0 else { return "—" }
    let formatted = ByteCountFormatter.string(
        fromByteCount: Int64(bytesPerSec),
        countStyle: .file
    )
    return "\(formatted)/s"
}

/// Footer that shows aggregate up/down byte-rate totals. Lives as its
/// own View so the periodic `@State` refresh stays scoped to this
/// sub-view — the same write inside `TaskManagerView`'s body
/// invalidated the parent every 500ms during a transfer, rebuilt the
/// Tables, and dropped row selection mid-click.
struct TransferSpeedsFooter: View {
    let connections: ActiveConnections
    @State private var totalSpeeds: (down: Double, up: Double) = (0, 0)

    var body: some View {
        HStack(spacing: Spacing.xsmall.rawValue) {
            speedBadge(
                glyph: "arrow.down",
                rate: totalSpeeds.down,
                tint: .accentColor
            )
            speedBadge(
                glyph: "arrow.up",
                rate: totalSpeeds.up,
                tint: .orange
            )
        }
        .task { await refreshLoop() }
    }

    private func speedBadge(glyph: String, rate: Double, tint: Color) -> some View {
        HStack(spacing: Spacing.xxsmall.rawValue) {
            Image(systemName: glyph)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
            Text(cellFormatSpeed(rate))
                .font(.caption.monospacedDigit())
                .foregroundStyle(rate > 0 ? .primary : .secondary)
        }
        .padding(.horizontal, .xsmall)
        .padding(.vertical, .xxxsmall)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(rate > 0 ? 0.15 : 0.07))
        )
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            let speeds = currentSpeeds()
            if speeds.down != totalSpeeds.down || speeds.up != totalSpeeds.up {
                totalSpeeds = speeds
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    private func currentSpeeds() -> (down: Double, up: Double) {
        var down = 0.0
        var up = 0.0
        for handle in connections.connections {
            for state in handle.filesVM.transfers.values where state.status == .running {
                switch state.direction {
                case .download:
                    down += state.speedBytesPerSec
                case .upload:
                    up += state.speedBytesPerSec
                }
            }
        }
        return (down, up)
    }
}

struct TransferFileCell: View {
    let row: AggregatedTransfer
    var body: some View {
        let state = cellLiveState(row)
        HStack(spacing: Spacing.xsmall.rawValue) {
            Image(systemName: state.direction == .download
                  ? "arrow.down.circle.fill"
                  : "arrow.up.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(transferTint(for: state))
                .font(.title3)
            Text(state.displayName)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct TransferProgressCell: View {
    let row: AggregatedTransfer
    var body: some View {
        let state = cellLiveState(row)
        VStack(alignment: .leading, spacing: Spacing.tiny.rawValue) {
            ProgressView(value: state.fraction)
                .progressViewStyle(.linear)
                .tint(transferTint(for: state))
            Text(cellProgressText(state))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

struct TransferSpeedCell: View {
    let row: AggregatedTransfer
    var body: some View {
        let state = cellLiveState(row)
        Text(state.status == .running ? cellFormatSpeed(state.speedBytesPerSec) : "—")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}

struct TransferStatusCell: View {
    let row: AggregatedTransfer
    var body: some View {
        let state = cellLiveState(row)
        switch state.status {
        case .running:
            statusPill(
                "Running",
                systemImage: "ellipsis",
                tint: state.direction == .download ? Color.accentColor : Color.orange
            )
        case .completed:
            statusPill("Done", systemImage: "checkmark", tint: .green)
        case .failed(let message):
            statusPill("Failed", systemImage: "exclamationmark.triangle.fill", tint: .red)
                .help(message)
        }
    }

    @ViewBuilder
    private func statusPill(_ title: LocalizedStringKey, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, .xsmall)
            .padding(.vertical, .tiny)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.15))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 0.5)
            )
    }
}

/// Direction + status → accent colour. Matches the per-server
/// TransferTile palette so the visual language is consistent across
/// the file-pane drawer and the all-servers Task Manager.
@MainActor
private func transferTint(for state: FilesViewModel.TransferState) -> Color {
    switch state.status {
    case .running:
        return state.direction == .download ? .accentColor : .orange
    case .completed:
        return .green
    case .failed:
        return .red
    }
}

struct TransferActionsCell: View {
    let row: AggregatedTransfer
    let onRemove: () -> Void
    var body: some View {
        let state = cellLiveState(row)
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
                    onRemove()
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
                    onRemove()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove")
            }
        }
    }
}

/// Flat row identity for the transfers table — pairs a `ConnectionHandle`
/// with one of its in-flight transfer states so the table can render
/// rows from multiple connections at once.
struct AggregatedTransfer: Identifiable, Hashable {
    let handle: ConnectionHandle
    let state: FilesViewModel.TransferState

    var id: String { "\(handle.id)/\(state.id)" }

    /// Identity-only equality: two snapshots of the same transfer are
    /// "equal" even if `bytesWritten`/`speed`/`status` differ. This
    /// keeps `aggregatedSnapshot` from churning every 100ms during an
    /// active transfer, which in turn keeps SwiftUI from reloading
    /// the underlying `NSTableView` and clearing the user's selection.
    /// Cells read the live, ever-changing state through
    /// `liveState(for:)` so the visual stays fresh.
    static func == (lhs: AggregatedTransfer, rhs: AggregatedTransfer) -> Bool {
        lhs.handle.id == rhs.handle.id && lhs.state.id == rhs.state.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(handle.id)
        hasher.combine(state.id)
    }
}
