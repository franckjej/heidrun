import CommonTools
import SwiftUI

/// Connection-tab rows for the close/quit confirmation: the master toggle,
/// the unanswered-quit timeout and the logout/restart skip.
struct DisconnectConfirmationSettings: View {
    @AppStorage(AppStorageKeys.confirmBeforeDisconnect) private var confirmBeforeDisconnect: Bool = true
    @AppStorage(AppStorageKeys.quitAutoConfirmSeconds)
    private var quitAutoConfirmSeconds: Int = DisconnectConfirmation.defaultQuitAutoConfirmSeconds
    @AppStorage(AppStorageKeys.skipQuitConfirmOnSessionEnd)
    private var skipQuitConfirmOnSessionEnd: Bool = true

    var body: some View {
        Toggle(
            "Warn before closing a connected window or quitting",
            isOn: $confirmBeforeDisconnect
        )
        caption("Asks for confirmation whenever closing a window or quitting Heidrun would disconnect you from a server.")
        Group {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small.rawValue) {
                Text("Quit automatically after")
                    .foregroundStyle(.secondary)
                Picker("", selection: $quitAutoConfirmSeconds) {
                    ForEach(DisconnectConfirmation.quitAutoConfirmChoices, id: \.self) { seconds in
                        if seconds == 0 {
                            Text("Never").tag(seconds)
                        } else {
                            Text(verbatim: Duration.seconds(seconds).formatted(.units(width: .wide)))
                                .tag(seconds)
                        }
                    }
                }
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 0)
            }
            caption("If the quit prompt goes unanswered, Heidrun quits after this delay so it can't hold up a restart or update.")
            Toggle(
                "Don't ask when logging out, restarting or shutting down",
                isOn: $skipQuitConfirmOnSessionEnd
            )
        }
        .disabled(!confirmBeforeDisconnect)
    }

    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
