import SwiftUI
import AppKit
import CommonTools

/// Single-row status strip rendered at the bottom of HostView via
/// `.safeAreaInset(edge: .bottom)`. Read-only; reflects whatever
/// HostState currently advertises.
struct StatusBar: View {
    let state: HostState
    let userCount: Int?    // nil until user-list event lands
    let transferCount: Int // placeholder

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(state.isConnected ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(identityLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Text(countsLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, .small)
        .frame(maxWidth: .infinity)
        .background(.clear)
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    "\(identityLabel) · \(countsLabel)",
                    forType: .string
                )
            }
        }
    }

    private var identityLabel: String {
        let nick = state.lastAttemptedSettings?.nickname ?? "—"
        let login = state.lastAttemptedSettings?.login ?? ""
        return login.isEmpty ? "\(nick)@\(state.serverName)" : "\(login)@\(state.serverName)"
    }

    private var countsLabel: String {
        "\(userCount.map { "\($0)" } ?? "—") users · \(transferCount) transfers"
    }
}
