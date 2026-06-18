import SwiftUI
import HeidrunCore
import HeidrunUI
import CommonTools

// MARK: - Border shape

/// Border shape used by `TransferTile`. Draws the top edge with both
/// corners, then the bottom edge with both corners, but never the
/// vertical leading / trailing rules — the result reads as a card
/// with corner-bracket accents instead of a fully outlined box.
///
/// Two separate sub-paths so the stroke renderer doesn't try to
/// connect top-right to bottom-right via the open right edge.
struct TransferTileBracket: Shape {
    var cornerRadius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        var path = Path()

        // Top half: top-left corner → top edge → top-right corner.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius),
            radius: radius,
            startAngle: .degrees(270),
            endAngle: .degrees(0),
            clockwise: false
        )

        // Bottom half: bottom-right corner → bottom edge → bottom-left
        // corner. Starts with a `move` so it stays a separate sub-path
        // — otherwise the stroker draws a phantom vertical right edge.
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(
            center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius),
            radius: radius,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )

        return path
    }
}

// MARK: - Tile

/// One card in the transfer drawer / Task Manager sheet. Lays out:
/// directional glyph + name + cancel button on the top row, progress
/// bar in the middle, status / speed on the bottom row. Colours
/// shift to match the transfer's state — accent while running,
/// muted when done, red when failed — so a glance reads the outcome
/// without parsing the text.
struct TransferTile: View {
    let state: FilesViewModel.TransferState
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxsmall.rawValue) {
            HStack(spacing: Spacing.xsmall.rawValue) {
                Image(systemName: directionGlyph)
                    .font(.title3)
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 0) {
                    Text(state.displayName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(statusLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Spacing.xsmall.rawValue)
                if state.status == .running {
                    Button(String(localized: "Cancel", bundle: .module), action: onCancel)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                }
            }

            // A completed transfer is 100% by definition — never show a
            // bar (a folder download with no server-reported size would
            // otherwise render a stuck empty bar). Running shows live
            // progress; failed shows how far it got.
            if state.status != .completed {
                ProgressView(value: state.fraction)
                    .progressViewStyle(.linear)
                    .tint(tint)
            }

            HStack(spacing: Spacing.xsmall.rawValue) {
                Text(bytesText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                if state.status == .running, let speed = speedText {
                    Text("•", bundle: .module)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(speed)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if case .failed(let reason) = state.status {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.xsmall)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.background.secondary)
        )
        .overlay(
            // Corner-bracket accent: full top + bottom rules + four
            // rounded corner arcs, with the vertical leading/trailing
            // edges intentionally open. Plays nicer than a full
            // 0.5pt stroke (which dropped edges on retina because of
            // sub-pixel rounding) and keeps the directional tint
            // legible without crowding the card.
            TransferTileBracket(cornerRadius: 10)
                .stroke(tint.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        )
    }

    private var directionGlyph: String {
        switch state.direction {
        case .download:
            return "arrow.down.circle.fill"
        case .upload:
            return "arrow.up.circle.fill"
        }
    }

    private var tint: Color {
        switch state.status {
        case .running:
            return state.direction == .download ? .accentColor : .orange
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    private var statusLabel: String {
        switch state.status {
        case .running:
            return state.direction == .download ? "Downloading" : "Uploading"
        case .completed:
            return state.direction == .download ? "Download complete" : "Upload complete"
        case .failed:
            return "Failed"
        }
    }

    private var bytesText: String {
        let total = ByteCountFormatter.string(fromByteCount: Int64(state.totalSize), countStyle: .file)
        switch state.status {
        case .running:
            let done = ByteCountFormatter.string(fromByteCount: Int64(state.bytesWritten), countStyle: .file)
            return "\(done) / \(total)"
        case .completed:
            return total
        case .failed:
            let done = ByteCountFormatter.string(fromByteCount: Int64(state.bytesWritten), countStyle: .file)
            return "\(done) / \(total)"
        }
    }

    private var speedText: String? {
        let rate = state.speedBytesPerSec
        guard rate > 0 else { return nil }
        let bps = ByteCountFormatter.string(fromByteCount: Int64(rate), countStyle: .file)
        return "\(bps)/s"
    }
}

// MARK: - Task Manager sheet

/// Modal sheet that exposes the full transfer queue — every running,
/// completed, and failed transfer in newest-first order. Lets the
/// user cancel any individual running transfer and clear out finished
/// rows. Same TransferTile rendering as the drawer so the visual
/// language stays consistent.
struct TransferTaskManagerSheet: View {
    let transfers: [FilesViewModel.TransferState]
    let onClear: () -> Void
    let onCancel: (HeidrunCore.TransferHandle) -> Void
    let onClose: () -> Void

    private var hasFinished: Bool {
        transfers.contains(where: { $0.status != .running })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.small.rawValue) {
                Label(String(localized: "Task Manager", bundle: .module), systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                if hasFinished {
                    Button(String(localized: "Clear Finished", bundle: .module), action: onClear)
                        .controlSize(.small)
                }
                Button(String(localized: "Close", bundle: .module), action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.small)
            }
            .padding(.small)
            Divider()
            if transfers.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Transfers", bundle: .module),
                    systemImage: "arrow.up.arrow.down.circle",
                    description: Text("Uploads and downloads will appear here while they're running and after they finish.", bundle: .module)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: Spacing.xsmall.rawValue) {
                        ForEach(transfers, id: \.id) { state in
                            TransferTile(state: state) {
                                onCancel(state.handle)
                            }
                        }
                    }
                    .padding(.small)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}
