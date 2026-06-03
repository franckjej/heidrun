/// The current threaded-news selection + the actions that operate on it,
/// published by `ThreadedNewsScreen` via `.focusedValue(\.newsActionContext,…)`
/// so the macOS "News" menu can drive the same actions as the in-window
/// toolbar. Closures call straight into the screen's action handlers, so
/// every surface shares one behavior.
///
/// `public` because the focused-value key (in the app target) references
/// the type; the closures + flags are the entire contract.
@MainActor
public struct NewsActionContext {
    public let hasSelection: Bool
    public let canEdit: Bool
    public let copyPost: () -> Void
    public let copyThread: () -> Void
    public let reply: () -> Void
    public let edit: () -> Void
    public let delete: () -> Void
    public let hasSelectedBundle: Bool
    public let copyBundleContents: () -> Void

    public init(
        hasSelection: Bool,
        canEdit: Bool,
        copyPost: @escaping () -> Void,
        copyThread: @escaping () -> Void,
        reply: @escaping () -> Void,
        edit: @escaping () -> Void,
        delete: @escaping () -> Void,
        hasSelectedBundle: Bool,
        copyBundleContents: @escaping () -> Void
    ) {
        self.hasSelection = hasSelection
        self.canEdit = canEdit
        self.copyPost = copyPost
        self.copyThread = copyThread
        self.reply = reply
        self.edit = edit
        self.delete = delete
        self.hasSelectedBundle = hasSelectedBundle
        self.copyBundleContents = copyBundleContents
    }
}
