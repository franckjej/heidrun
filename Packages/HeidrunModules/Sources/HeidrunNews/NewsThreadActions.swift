import AppKit
import HeidrunCore

/// Bundles the per-thread actions (edit / delete / copy-post /
/// copy-thread) that the four threaded-news UI surfaces (context menu,
/// body-pane buttons, ellipsis overflow menu, keyboard shortcuts) all
/// share. One target = the four surfaces can't drift apart.
///
/// `onEdit` / `onConfirmDelete` are dispatch callbacks the host view
/// (`ThreadedNewsScreen`) wires to its `@State editThreadTarget` /
/// `@State deleteThreadTarget` bindings.
@MainActor
struct NewsThreadActions {
    let viewModel: ThreadedNewsViewModel
    let ownNickname: String
    let onEdit: (NewsThread) -> Void
    let onConfirmDelete: (NewsThread) -> Void
    let onReply: (NewsThread) -> Void

    /// "Re: " prefix the reply composer pre-fills with. Kept as a
    /// constant so callers don't have to remember to skip it on a
    /// chain (`Re: Re: Re: …`).
    static let replyTitlePrefix = "Re: "

    /// Title to pre-fill the reply sheet with. Strips a leading `Re: `
    /// from the parent so deep chains stay one `Re:` deep — mirrors
    /// the convention every news/mail client has used since the 80s.
    static func replyTitle(forParent parentTitle: String) -> String {
        var trimmed = parentTitle.trimmingCharacters(in: .whitespaces)
        while trimmed.lowercased().hasPrefix(replyTitlePrefix.lowercased()) {
            trimmed = String(trimmed.dropFirst(replyTitlePrefix.count))
                .trimmingCharacters(in: .whitespaces)
        }
        return replyTitlePrefix + trimmed
    }

    /// Author-ownership gate. Hide Edit surfaces on posts the local
    /// user didn't write — the server enforces ownership anyway, but
    /// hiding avoids the awkward "delete worked, post failed" partial.
    /// Returns false for blank authors / blank nicknames as a
    /// defensive fallback.
    func canEdit(_ thread: NewsThread) -> Bool {
        guard let author = thread.elements.first?.author,
              !author.isEmpty,
              !ownNickname.isEmpty
        else { return false }
        return author == ownNickname
    }

    /// Copy just the selected post (header + body) to the general
    /// pasteboard. No-op when the thread isn't in the VM's loaded
    /// list.
    func copyPost(_ thread: NewsThread) {
        guard let text = viewModel.copyText(threadID: thread.threadID, scope: .post)
        else { return }
        Self.writeToPasteboard(text)
    }

    /// Copy the selected post plus every descendant (depth-first by
    /// date) to the general pasteboard.
    func copyThread(_ thread: NewsThread) {
        guard let text = viewModel.copyText(threadID: thread.threadID, scope: .thread)
        else { return }
        Self.writeToPasteboard(text)
    }

    /// Gather a folder/category's whole content and put it on the general
    /// pasteboard. No-op when the gather yields nothing (empty folder or
    /// a fetch error — `viewModel.lastError` surfaces the latter).
    func copyContents(_ bundle: NewsBundle) async {
        guard let text = await viewModel.contentsText(for: bundle) else { return }
        Self.writeToPasteboard(text)
    }

    private static func writeToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
