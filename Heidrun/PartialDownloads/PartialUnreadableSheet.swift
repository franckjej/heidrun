import SwiftUI
import CommonTools

/// Fallback sheet for `.heidrunpart` files whose resume xattr is
/// missing, malformed, or uses an unsupported schema. The file itself
/// is still on disk, so we offer Reveal / Delete (to the Trash) /
/// dismiss rather than trying to recover a resume.
struct PartialUnreadableSheet: View {
    let value: PartialDownloadUnreadable
    let onReveal: () -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .imageScale(.large)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Couldn't read resume info")
                        .font(.title3.bold())
                    Text(value.reason)
                        .foregroundStyle(.secondary)
                    Text(value.url.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            HStack {
                Button("Delete", role: .destructive, action: onDelete)
                Spacer()
                Button("Reveal in Finder", action: onReveal)
                Button("OK", role: .cancel, action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.medium)
        .frame(width: 440)
    }
}
