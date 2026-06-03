import SwiftUI
import CommonTools

/// Shown while HostState is in `.connecting`. Offers a Cancel button that
/// transitions back to `.disconnected` and cancels the underlying Task.
///
/// When the coordinator is mid-cycle (`reconnectStatus` non-nil), a
/// secondary line renders the attempt counter.
struct ConnectingPane: View {
    let serverName: String
    let reconnectStatus: (attempt: Int, max: Int)?
    let onCancel: () -> Void

    init(
        serverName: String,
        reconnectStatus: (attempt: Int, max: Int)? = nil,
        onCancel: @escaping () -> Void
    ) {
        self.serverName = serverName
        self.reconnectStatus = reconnectStatus
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
            Text("Connecting to \(serverName)…")
                .font(.headline)
            if let status = reconnectStatus {
                Text("Reconnecting — attempt \(status.attempt) of \(status.max)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.bordered)
        }
        .padding(.xlarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
