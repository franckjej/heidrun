import SwiftUI
import HeidrunCore

/// The four-item menu (Edit / Delete / Copy Post / Copy Thread) shared
/// by the thread-row context menu and the body-pane "•••" overflow
/// menu. Edit hides itself when `actions.canEdit(thread) == false`.
@MainActor
struct NewsActionsMenuItems: View {
    let actions: NewsThreadActions
    let thread: NewsThread

    var body: some View {
        Button("Reply…") { actions.onReply(thread) }
            .disabled(!actions.viewModel.permits(.postNews))
        Divider()
        if actions.canEdit(thread) {
            Button("Edit…") { actions.onEdit(thread) }
                .disabled(!actions.viewModel.permits(.postNews))
        }
        Button("Delete…", role: .destructive) { actions.onConfirmDelete(thread) }
            .disabled(!actions.viewModel.permits(.deleteArticles))
        Divider()
        Button("Copy Post") { actions.copyPost(thread) }
        Button("Copy Thread") { actions.copyThread(thread) }
    }
}
