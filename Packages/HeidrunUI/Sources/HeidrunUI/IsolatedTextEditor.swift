import SwiftUI
import AppKit

/// Multi-line text input that doesn't dirty the enclosing
/// `DocumentGroup` document on typing.
///
/// `SwiftUI.TextEditor` wraps `NSTextView`, and `NSTextView` walks the
/// AppKit responder chain — `view → window → window controller →
/// NSDocument` — to find an `UndoManager` to register typing undos
/// against. Inside a `DocumentGroup`-hosted window that resolves to
/// the document's own manager, so every keystroke marks the document
/// "edited" and AppKit appends "— Edited" to the navigation subtitle
/// + autosaves to a UUID-named file + prompts "Save changes?" on
/// close. That's the wrong UX for every text input in Heidrun
/// (chat, news editor, file-info comment), where the document is just
/// a launch vehicle for the bookmark rather than an editable document.
///
/// `SwiftUI` won't let us swap the `\.undoManager` environment value
/// from inside a view — the env key is read-only on Swift 6. So we
/// drop a level and own the NSTextView directly: the subclass below
/// overrides `undoManager` to return a shared, app-lifetime instance,
/// breaking the responder-chain walk. (Shared rather than per-view
/// because a short-lived NSUndoManager leaks itself — see the property.)
public struct IsolatedTextEditor: NSViewRepresentable {
    @Binding public var text: String
    public var font: NSFont
    public var minHeight: CGFloat
    public var maxHeight: CGFloat?
    public var isRichText: Bool
    /// Invoked when the user presses ⌘↵ inside the text view. Use for
    /// "send on Cmd+Enter" semantics in chat composers etc. `nil`
    /// leaves the key combination unhandled.
    public var onSubmit: (() -> Void)?
    /// When `true` the text view becomes first responder once it's
    /// installed in a window. Match `TextEditor` + `.focused($flag)`
    /// + `.onAppear { flag = true }` for callers that want the input
    /// ready to type into immediately on view appear.
    public var autoFocus: Bool
    /// Recall the previous (older) history entry — invoked on ↑ when the
    /// caret is on the first line. Return the text to load, or `nil` to
    /// leave the field unchanged. A `nil` callback leaves ↑ behaving
    /// normally (cursor movement).
    public var onHistoryPrevious: (() -> String?)?
    /// Recall the next (newer) history entry — invoked on ↓ when the
    /// caret is on the last line. Return the text to load, or `nil` to
    /// fall through to normal cursor movement.
    public var onHistoryNext: (() -> String?)?
    /// Invoked when the user edits (any key other than the history
    /// arrows) so the owner can end history navigation.
    public var onEdit: (() -> Void)?

    public init(
        text: Binding<String>,
        font: NSFont = .preferredFont(forTextStyle: .body),
        minHeight: CGFloat = 50,
        maxHeight: CGFloat? = nil,
        isRichText: Bool = false,
        autoFocus: Bool = false,
        onSubmit: (() -> Void)? = nil,
        onHistoryPrevious: (() -> String?)? = nil,
        onHistoryNext: (() -> String?)? = nil,
        onEdit: (() -> Void)? = nil
    ) {
        self._text = text
        self.font = font
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.isRichText = isRichText
        self.autoFocus = autoFocus
        self.onSubmit = onSubmit
        self.onHistoryPrevious = onHistoryPrevious
        self.onHistoryNext = onHistoryNext
        self.onEdit = onEdit
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let textView = IsolatedNSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = isRichText
        textView.allowsUndo = true
        textView.font = font
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        textView.string = text
        textView.onCommandSubmit = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onSubmit?()
        }
        textView.onHistoryPrevious = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onHistoryPrevious?()
        }
        textView.onHistoryNext = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onHistoryNext?()
        }
        textView.onEdit = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onEdit?()
        }

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        if autoFocus {
            // Defer until the view is in a window — `makeFirstResponder`
            // before the view is attached is a no-op.
            DispatchQueue.main.async { [weak textView] in
                textView?.window?.makeFirstResponder(textView)
            }
        }
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? IsolatedNSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.font = font
        textView.onCommandSubmit = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onSubmit?()
        }
        textView.onHistoryPrevious = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onHistoryPrevious?()
        }
        textView.onHistoryNext = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onHistoryNext?()
        }
        textView.onEdit = { [weak coordinator = context.coordinator] in
            coordinator?.parent.onEdit?()
        }
    }

    public static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        // Clear the shared manager only on real teardown — not on blur — so
        // it can't retain this torn-down view's text storage (which would
        // leak the view), while a composer's undo survives focus churn
        // (e.g. Chat's live transcript bouncing first responder).
        IsolatedNSTextView.sharedUndoManager.removeAllActions()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: IsolatedTextEditor

        init(_ parent: IsolatedTextEditor) {
            self.parent = parent
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

/// `NSTextView` that owns its `UndoManager` rather than borrowing the
/// responder chain's. This is what stops chat / news / file-comment
/// typing from dirtying the `DocumentGroup` document. Also catches
/// ⌘↵ so a chat composer can wire "send on Cmd+Enter" without
/// installing a global key monitor.
final class IsolatedNSTextView: NSTextView {
    /// One shared, app-lifetime undo manager for every isolated composer —
    /// NOT one per view. `NSUndoManager` (with `groupsByEvent`) arms a GCD
    /// dispatch source whose handler retains the manager; that cycle is
    /// only broken in the manager's own dealloc, so a short-lived per-view
    /// manager never deallocates and leaks one instance per window
    /// open/close. A single instance that lives for the app's lifetime
    /// can't grow. It's still a non-document manager, so typing stays out
    /// of the `DocumentGroup` document's undo stack (the isolation goal).
    fileprivate static let sharedUndoManager = UndoManager()

    /// Called when the user presses ⌘↵. Assigned by `IsolatedTextEditor`.
    var onCommandSubmit: (() -> Void)?
    /// ↑ on the first line — return the older history entry to load, or nil.
    var onHistoryPrevious: (() -> String?)?
    /// ↓ on the last line — return the newer history entry to load, or nil.
    var onHistoryNext: (() -> String?)?
    /// Any non-history key — lets the owner end history navigation.
    var onEdit: (() -> Void)?

    override var undoManager: UndoManager? {
        Self.sharedUndoManager
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Handle ⌘Z / ⇧⌘Z here. The composer registers typing undo on the
        // shared manager, but the Edit ▸ Undo menu item operates on the
        // DocumentGroup document's manager — so the menu never sees these
        // edits. Performing undo/redo directly while we're first responder
        // routes the command to the right manager and consumes the event.
        guard event.modifierFlags.contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "z",
              window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        let manager = Self.sharedUndoManager
        if event.modifierFlags.contains(.shift) {
            if manager.canRedo { manager.redo(); return true }
        } else if manager.canUndo {
            manager.undo()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // ⌘↵ (Return with Command held) → invoke the submit closure.
        if event.modifierFlags.contains(.command),
           event.keyCode == 36 || event.keyCode == 76 {
            onCommandSubmit?()
            return
        }
        // Shell-style history recall, edge-triggered so it doesn't fight
        // multi-line cursor movement: ↑ recalls older only on the first
        // line, ↓ recalls newer only on the last line.
        if event.keyCode == 126, let recall = onHistoryPrevious, caretOnFirstLine {
            // Consume even at the oldest entry — there's nowhere above to
            // move the caret to anyway, and we don't want to end nav.
            if let recalled = recall() { loadRecalledText(recalled) }
            return
        }
        if event.keyCode == 125, let recall = onHistoryNext, caretOnLastLine {
            if let recalled = recall() {
                loadRecalledText(recalled)
                return
            }
            // recall() == nil → not navigating: fall through to normal ↓.
        }
        // Any other key edits the field — end history navigation.
        onEdit?()
        super.keyDown(with: event)
    }

    /// Replace the field with a recalled history entry, caret at the end,
    /// and push the change through the SwiftUI binding (setting `.string`
    /// directly doesn't fire the delegate's `textDidChange`).
    private func loadRecalledText(_ newText: String) {
        string = newText
        setSelectedRange(NSRange(location: (newText as NSString).length, length: 0))
        didChangeText()
    }

    /// True when the caret sits on the first display line (no newline
    /// before it) — the gate for ↑ recalling history.
    private var caretOnFirstLine: Bool {
        let caret = selectedRange().location
        return !(string as NSString).substring(to: caret).contains("\n")
    }

    /// True when the caret/selection ends on the last line (no newline
    /// after it) — the gate for ↓ recalling history.
    private var caretOnLastLine: Bool {
        let selection = selectedRange()
        let end = min(selection.location + selection.length, (string as NSString).length)
        return !(string as NSString).substring(from: end).contains("\n")
    }
}
