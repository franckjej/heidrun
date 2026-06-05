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

    public init(
        text: Binding<String>,
        font: NSFont = .preferredFont(forTextStyle: .body),
        minHeight: CGFloat = 50,
        maxHeight: CGFloat? = nil,
        isRichText: Bool = false,
        autoFocus: Bool = false,
        onSubmit: (() -> Void)? = nil
    ) {
        self._text = text
        self.font = font
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.isRichText = isRichText
        self.autoFocus = autoFocus
        self.onSubmit = onSubmit
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
        // ⌘↵ (Return with Command held) → invoke the submit closure;
        // anything else falls through to NSTextView's default
        // (newline insertion, navigation keys, etc).
        if event.modifierFlags.contains(.command),
           event.keyCode == 36 || event.keyCode == 76 {
            onCommandSubmit?()
            return
        }
        super.keyDown(with: event)
    }
}
