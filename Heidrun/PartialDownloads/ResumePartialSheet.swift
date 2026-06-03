import SwiftUI
import HeidrunCore
import CommonTools

/// Floats over the host's root view when the user double-clicks a
/// `.heidrunpart` whose xattr parsed cleanly. Offers the three useful
/// actions (resume / reveal / cancel) without exposing any of the
/// reconnect plumbing — `HostState.requestPartialResume(_:)` owns that.
struct ResumePartialSheet: View {
    let request: PartialResumeRequest
    let onResume: () -> Void
    let onReveal: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Resume \(request.metadata.remoteFileName)?")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 4) {
                Text("From \(request.metadata.serverName)")
                    .foregroundStyle(.secondary)
                Text(verbatim: "\(request.metadata.serverAddress):\(request.metadata.serverPort.formatted(.number.grouping(.never)))")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                Text("\(byteString(request.bytesOnDisk)) of \(byteString(request.metadata.totalSize)) downloaded")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Reveal in Finder", action: onReveal)
                    .buttonStyle(.bordered)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Resume", action: onResume)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.medium)
        .frame(width: 440)
    }

    private func byteString(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }
}
