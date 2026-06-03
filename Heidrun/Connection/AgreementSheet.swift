import SwiftUI
import CommonTools

/// Modal sheet shown over `ConnectingPane` whenever the server pushes
/// an agreement banner (transID 109). The user either agrees (which
/// just dismisses the sheet — no trans=121 goes on the wire; see
/// `HostState.acceptAgreement` for the reasoning) or cancels, which
/// disconnects the session.
struct AgreementSheet: View {
    let prompt: AgreementPrompt
    var onAccept: () -> Void
    var onDecline: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small.rawValue) {
            Text("Server Agreement")
                .font(.title3)
                .fontWeight(.semibold)

            ScrollView {
                Text(prompt.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(.small)
            }
            .frame(minHeight: 180, maxHeight: 320)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: .cornerMed, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: .cornerMed, style: .continuous))

            HStack {
                Button("Cancel", role: .cancel) { onDecline() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Agree") { onAccept() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.small)
        .frame(minWidth: 480)
    }
}
