import SwiftUI
import HeidrunCore
import CommonTools

/// Compact drawer under the file list: at most one upload + one download
/// "primary" tile (newest running, falling back to newest finished). The
/// full history lives behind Task Manager.
struct TransferDrawer: View {
    let viewModel: FilesViewModel
    /// Highest transfer ID the user closed the drawer on.
    @Binding var dismissedThroughID: UInt32?
    let showTaskManager: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xsmall.rawValue) {
            HStack(spacing: Spacing.xsmall.rawValue) {
                Label(String(localized: "Transfers", bundle: .module), systemImage: "arrow.up.arrow.down.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if hasFinishedTransfers {
                    Button(String(localized: "Clear", bundle: .module)) {
                        viewModel.clearFinishedTransfers()
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
                }
                Button {
                    showTaskManager()
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
                if !hasRunningTransfers {
                    Button {
                        dismissedThroughID = viewModel.transfers.keys.max()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
                    .help(String(localized: "Hide Transfers", bundle: .module))
                }
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

    /// Download first when both directions exist (mirrors the
    /// arrow.down.arrow.up reading direction).
    private var visibleTransfers: [FilesViewModel.TransferState] {
        [
            primaryTransfer(direction: .download),
            primaryTransfer(direction: .upload)
        ].compactMap { $0 }
    }

    /// Hidden once closed until a newer transfer starts; running
    /// transfers always keep it up.
    nonisolated static func isShown(
        _ transfers: [UInt32: FilesViewModel.TransferState],
        dismissedThroughID: UInt32?
    ) -> Bool {
        guard let newestID = transfers.keys.max() else { return false }
        guard let dismissedThroughID else { return true }
        return newestID > dismissedThroughID
            || transfers.values.contains(where: { $0.status == .running })
    }

    private var hasRunningTransfers: Bool {
        viewModel.transfers.values.contains(where: { $0.status == .running })
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
}
