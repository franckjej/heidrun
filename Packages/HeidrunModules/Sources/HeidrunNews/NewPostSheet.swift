import SwiftUI
import CommonTools
import HeidrunUI

/// Modal sheet for posting a new thread (top-level or reply). Mirrors
/// `EditPostSheet` in shape: title field on top, multi-line body, ⌘⏎
/// posts, Esc cancels.
///
/// `sheetTitle` + `initialTitle` let the same sheet serve as both the
/// "New Post" and "Reply" composer — the reply path opens with
/// "Re: <parent title>" pre-filled so the user just types the body and
/// hits ⌘⏎. The server doesn't care about the title text for threading
/// (parentThreadID is the only signal) but the row labelling falls out
/// of the title, so the "Re:" convention keeps the tree readable.
@MainActor
struct NewPostSheet: View {
    let onSubmit: @Sendable (String, String) async -> Void
    let sheetTitle: LocalizedStringKey

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var postBody = ""
    @State private var isSubmitting = false
    @FocusState private var titleFocused: Bool

    init(
        title sheetTitle: LocalizedStringKey = "New Post",
        initialTitle: String = "",
        onSubmit: @escaping @Sendable (String, String) async -> Void
    ) {
        self.sheetTitle = sheetTitle
        self.onSubmit = onSubmit
        _title = State(initialValue: initialTitle)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small.rawValue) {
            Text(sheetTitle)
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)
                .focused($titleFocused)

            TextEditor(text: $postBody)
                .font(.body)
                .frame(minHeight: 160)
                .padding(.xxsmall)
                .background(
                    RoundedRectangle(cornerRadius: .cornerHigh, style: .continuous)
                        .fill(.background.secondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: .cornerHigh, style: .continuous)
                        .stroke(.separator, lineWidth: 0.5)
                )

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Post")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isSubmitting || isEmpty)
            }
        }
        .padding(.small)
        .frame(minWidth: 420, minHeight: 320)
        .closeOnCmdW { dismiss() }
        .onAppear { titleFocused = true }
    }

    private var isEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && postBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = postBody
        guard !trimmedTitle.isEmpty else { return }
        isSubmitting = true
        Task { @MainActor in
            await onSubmit(trimmedTitle, body)
            isSubmitting = false
            dismiss()
        }
    }
}
