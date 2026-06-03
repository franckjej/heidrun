import SwiftUI
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
            }
            Spacer()
            Text("\(userCount.map { "\($0)" } ?? "—") users · \(transferCount) transfers")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.trailing, .small)
        }
        .frame(maxWidth: .infinity)
        .background(.clear)
    }

    private var identityLabel: String {
        let nick = state.lastAttemptedSettings?.nickname ?? "—"
        let login = state.lastAttemptedSettings?.login ?? ""
        return login.isEmpty ? "\(nick)@\(state.serverName)" : "\(login)@\(state.serverName)"
    }
}
