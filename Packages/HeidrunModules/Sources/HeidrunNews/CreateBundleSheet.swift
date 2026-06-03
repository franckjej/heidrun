import SwiftUI
import HeidrunUI
import CommonTools

/// Modal for creating a new news folder or category under the current
/// path. Hands the typed name + kind back to the caller's submit
/// closure, which in turn calls `ThreadedNewsViewModel.createBundle`.
struct CreateBundleSheet: View {
    var onSubmit: @Sendable (String, Bool) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: Kind = .folder
    @State private var isSubmitting = false
    @FocusState private var nameFocused: Bool

    private enum Kind: Hashable {
        case folder, category
        var isCategory: Bool { self == .category }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small.rawValue) {
            Text("New News Folder")
                .font(.title3)
                .fontWeight(.semibold)

            Picker("Kind", selection: $kind) {
                Text("Folder").tag(Kind.folder)
                Text("Category").tag(Kind.category)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($nameFocused)
                .onSubmit(submit)

            Text(kind == .folder
                 ? "A folder holds more folders or categories."
                 : "A category holds news threads (posts).")
                .font(.caption)
                .foregroundStyle(.secondary)

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
                        Text("Create")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isSubmitting || trimmedName.isEmpty)
            }
        }
        .padding(.small)
        .frame(minWidth: 360)
        .onAppear { nameFocused = true }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        let finalName = trimmedName
        guard !finalName.isEmpty else { return }
        let isCategory = kind.isCategory
        isSubmitting = true
        Task { @MainActor in
            await onSubmit(finalName, isCategory)
            isSubmitting = false
            dismiss()
        }
    }
}
