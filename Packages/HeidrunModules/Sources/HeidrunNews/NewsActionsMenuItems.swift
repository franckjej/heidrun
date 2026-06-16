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
        Button(String(localized: "Reply…", bundle: .module)) { actions.onReply(thread) }
            .disabled(!actions.viewModel.permits(.postNews))
        Divider()
        if actions.canEdit(thread) {
            Button(String(localized: "Edit…", bundle: .module)) { actions.onEdit(thread) }
                .disabled(!actions.viewModel.permits(.postNews))
        }
        Button(String(localized: "Delete…", bundle: .module), role: .destructive) { actions.onConfirmDelete(thread) }
            .disabled(!actions.viewModel.permits(.deleteArticles))
        Divider()
        Button(String(localized: "Copy Post", bundle: .module)) { actions.copyPost(thread) }
        Button(String(localized: "Copy Thread", bundle: .module)) { actions.copyThread(thread) }
    }
}
