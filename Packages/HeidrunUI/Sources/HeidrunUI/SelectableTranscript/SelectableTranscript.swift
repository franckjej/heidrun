import AppKit
import SwiftUI
import CommonTools

/// SwiftUI view that renders `[TranscriptLine]` in a read-only NSTextView
/// with native drag-select + ⌘C.
///
/// Scroll behaviour follows a `TranscriptScrollAnchor` when one is
/// supplied: the auto-follow-bottom intent and last scroll offset live in
/// the anchor (owned by a long-lived view-model), so they survive the
/// `NSScrollView` teardown/rebuild that a feature switch triggers. Without
/// an anchor it falls back to the best-effort "stay at bottom if you were
/// at the bottom" heuristic sampled from the live view.
public struct SelectableTranscript: NSViewRepresentable {
    private let lines: [TranscriptLine]
    private let scrollAnchor: TranscriptScrollAnchor?
    @Environment(\.heidrunContentSize) private var contentSize

    public init(lines: [TranscriptLine], scrollAnchor: TranscriptScrollAnchor? = nil) {
        self.lines = lines
        self.scrollAnchor = scrollAnchor
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(anchor: scrollAnchor)
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

        // Record scroll intent only from user-driven live scrolls (trackpad,
        // wheel, scroller drag). Layout- and programmatic-scroll changes don't
        // post these, so they can't clobber the anchor on rebuild.
        context.coordinator.scrollView = scrollView
        for name: NSNotification.Name in [
            NSScrollView.didLiveScrollNotification,
            NSScrollView.didEndLiveScrollNotification
        ] {
            NotificationCenter.default.addObserver(
                context.coordinator,
                selector: #selector(Coordinator.userDidScroll(_:)),
                name: name,
                object: scrollView
            )
        }
        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SelectableTextView,
              let storage = textView.textStorage else { return }

        // Capture intent BEFORE mutating the text. With an anchor it's the
        // persisted user intent (survives teardown); without one, fall back
        // to sampling the live geometry as before.
        let followsBottom = scrollAnchor?.followsBottom
            ?? Self.isAtBottom(scrollView: scrollView, tolerance: 4)
        let restoreOffsetY = scrollAnchor.flatMap { followsBottom ? nil : $0.offsetY }

        let built = TranscriptAttributedStringBuilder.build(
            lines: lines, contentSize: contentSize
        )

        storage.beginEditing()
        storage.setAttributedString(built)
        storage.endEditing()

        // Defer past this view-update cycle; the scroll helpers force layout
        // so they target the NEW geometry, not the stale one.
        DispatchQueue.main.async {
            if followsBottom {
                Self.scrollToBottom(scrollView: scrollView)
            } else if let restoreOffsetY {
                Self.scroll(scrollView: scrollView, toOffsetY: restoreOffsetY)
            }
        }
    }

    fileprivate static func isAtBottom(scrollView: NSScrollView, tolerance: CGFloat) -> Bool {
        guard let documentView = scrollView.documentView else { return true }
        let visible = scrollView.contentView.bounds
        let maxY = documentView.bounds.maxY
        return (visible.maxY + tolerance) >= maxY
    }

    private static func scrollToBottom(scrollView: NSScrollView) {
        guard let contentHeight = laidOutContentHeight(scrollView: scrollView) else { return }
        let visibleHeight = scrollView.contentView.bounds.height
        scroll(scrollView: scrollView, toOffsetY: contentHeight - visibleHeight)
    }

    /// Scroll to an absolute offset, clamped to the valid range for the
    /// freshly-laid-out content.
    private static func scroll(scrollView: NSScrollView, toOffsetY offsetY: CGFloat) {
        guard let contentHeight = laidOutContentHeight(scrollView: scrollView) else { return }
        let visibleHeight = scrollView.contentView.bounds.height
        let maxOffsetY = max(0, contentHeight - visibleHeight)
        let targetY = min(max(0, offsetY), maxOffsetY)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// Force glyph layout and return the document's pixel height. Without the
    /// `ensureLayout`, sending via ⌘-Return (which keeps focus in the input,
    /// so no incidental layout fires) measures the stale, pre-message height.
    private static func laidOutContentHeight(scrollView: NSScrollView) -> CGFloat? {
        guard let textView = scrollView.documentView as? SelectableTextView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return nil }
        layoutManager.ensureLayout(for: container)
        return layoutManager.usedRect(for: container).height
            + 2 * textView.textContainerInset.height
    }

    /// Bridges AppKit user-scroll notifications into the persisted anchor.
    @MainActor
    public final class Coordinator: NSObject {
        private let anchor: TranscriptScrollAnchor?
        weak var scrollView: NSScrollView?

        init(anchor: TranscriptScrollAnchor?) {
            self.anchor = anchor
        }

        @objc func userDidScroll(_ notification: Notification) {
            guard let anchor, let scrollView else { return }
            anchor.followsBottom = SelectableTranscript.isAtBottom(scrollView: scrollView, tolerance: 4)
            anchor.offsetY = scrollView.contentView.bounds.origin.y
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
