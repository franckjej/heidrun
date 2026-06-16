import SwiftUI
import HeidrunCore

/// Presents the server's agreement banner with accept / decline actions.
///
/// The view is intentionally plain: a scrollable text block on top, a
/// nickname / icon row in the middle, and two buttons at the bottom.
public struct AgreementView: View {
    @State private var viewModel: AgreementViewModel
    @State private var working = false

    public init(viewModel: AgreementViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 12) {
            if let text = viewModel.text {
                ScrollView {
                    Text(text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ContentUnavailableView(
                    String(localized: "Waiting for the server agreement…", bundle: .module),
                    systemImage: "doc.text"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack {
                TextField(String(localized: "Nickname", bundle: .module), text: $viewModel.nickname)
                    .textFieldStyle(.roundedBorder)

                Stepper(value: $viewModel.icon, in: 0...UInt16.max) {
                    HStack {
                        Text("Icon", bundle: .module)
                        Text("\(viewModel.icon.formatted(.number.grouping(.never)))", bundle: .module)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize()
            }

            HStack {
                Button(String(localized: "Decline", bundle: .module), role: .destructive) {
                    Task {
                        working = true
                        await viewModel.decline()
                        working = false
                    }
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(String(localized: "Agree", bundle: .module)) {
                    Task {
                        working = true
                        try? await viewModel.accept()
                        working = false
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.text == nil || viewModel.nickname.isEmpty)
            }
            .disabled(working)
        }
        .padding()
        .task { await viewModel.observe() }
    }
}
