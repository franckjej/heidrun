import SwiftUI
import CommonTools
import HeidrunCore
import HeidrunUI

/// Modal sheet for editing an existing news post. Pre-filled with the
/// current title + body; Save fires the supplied `onSave` callback
/// (which the host wires to `ThreadedNewsViewModel.editThread`).
///
/// Mirrors `NewPostSheet` in shape so the user experience reads the
/// same: title field on top, multi-line body, Cancel + Save at the
/// bottom. ⌘⏎ saves, Esc cancels.
@MainActor
struct EditPostSheet: View {
    let thread: NewsThread
    var onSave: @Sendable (String, String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var postBody: String
    @State private var isSubmitting = false
    @FocusState private var titleFocused: Bool

    init(
        thread: NewsThread,
        onSave: @escaping @Sendable (String, String) async -> Void
    ) {
        self.thread = thread
        self.onSave = onSave
        let element = thread.elements.first
        self._title = State(initialValue: element?.title ?? "")
        self._postBody = State(initialValue: element?.body ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small.rawValue) {
            Text("Edit Post")
                .font(.title3)
                .fontWeight(.semibold)

            TextField("Subject", text: $title)
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
                        Text("Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isSubmitting || isTitleEmpty)
            }
        }
        .padding(.small)
        .frame(minWidth: 420, minHeight: 320)
        .closeOnCmdW { dismiss() }
        .onAppear { titleFocused = true }
    }

    private var isTitleEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = postBody
        guard !trimmedTitle.isEmpty else { return }
        isSubmitting = true
        Task { @MainActor in
            await onSave(trimmedTitle, body)
            isSubmitting = false
            dismiss()
        }
    }
}
