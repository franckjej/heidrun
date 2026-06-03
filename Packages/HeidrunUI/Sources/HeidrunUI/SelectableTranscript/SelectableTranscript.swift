import AppKit
import SwiftUI
import CommonTools

/// SwiftUI view that renders `[TranscriptLine]` in a read-only NSTextView
/// with native drag-select + ⌘C. Auto-scrolls to the bottom on update
/// when the user was already at the bottom before the change.
public struct SelectableTranscript: NSViewRepresentable {
    private let lines: [TranscriptLine]
    @Environment(\.heidrunContentSize) private var contentSize

    public init(lines: [TranscriptLine]) {
        self.lines = lines
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true

        let textView = SelectableTextView()
        // Self-delegating so the link-click hook in SelectableTextView
        // fires; needs to be set before any text is installed so the
        // delegate is in place before the first click hit-test.
        textView.delegate = textView
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.allowsUndo = false
        textView.usesFontPanel = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.size = NSSize(
            width: 0, height: CGFloat.greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SelectableTextView,
              let storage = textView.textStorage else { return }

        let wasAtBottom = Self.isAtBottom(scrollView: scrollView, tolerance: 4)
        let built = TranscriptAttributedStringBuilder.build(
            lines: lines, contentSize: contentSize
        )

        storage.beginEditing()
        storage.setAttributedString(built)
        storage.endEditing()

        if wasAtBottom {
            // Defer past this view-update cycle; `scrollToBottom` forces
            // layout so it targets the NEW bottom, not the stale one.
            DispatchQueue.main.async {
                Self.scrollToBottom(scrollView: scrollView)
            }
        }
    }

    private static func isAtBottom(scrollView: NSScrollView, tolerance: CGFloat) -> Bool {
        guard let documentView = scrollView.documentView else { return true }
        let visible = scrollView.contentView.bounds
        let maxY = documentView.bounds.maxY
        return (visible.maxY + tolerance) >= maxY
    }

    private static func scrollToBottom(scrollView: NSScrollView) {
        guard let textView = scrollView.documentView as? SelectableTextView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }
        // Force glyph layout so the height reflects the just-set text. Without
        // this, sending via ⌘-Return (which keeps focus in the input, so no
        // incidental layout fires) scrolls to the stale, pre-message bottom.
        layoutManager.ensureLayout(for: container)
        let contentHeight = layoutManager.usedRect(for: container).height
            + 2 * textView.textContainerInset.height
        let visibleHeight = scrollView.contentView.bounds.height
        let targetY = max(0, contentHeight - visibleHeight)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }
}
