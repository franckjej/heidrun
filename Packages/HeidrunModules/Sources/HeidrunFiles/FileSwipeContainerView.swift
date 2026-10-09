import AppKit
import CommonTools
import HeidrunUI

/// Hosts the file list's scroll view and, during a two-finger swipe, a
/// Safari-style slide of page snapshots above it.
final class FileSwipeContainerView: NSView {
    let scrollView: NSScrollView
    /// Density the table currently draws at; kept in sync by the owner.
    var contentSize = ContentSize.default
    private let slideView = SwipeSlideView()

    init(scrollView: NSScrollView) {
        self.scrollView = scrollView
        super.init(frame: .zero)
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)
        addSubview(slideView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Bitmap of the rows area as it looks right now (header excluded).
    func capturePage() -> PageSnapshot? {
        PageSnapshot.capture(of: scrollView, rect: pageRect, contentSize: contentSize)
    }

    /// Start a slide over the rows; the live column header stays put above.
    func beginSlide(back: PageSnapshot?, forward: PageSnapshot?) {
        slideView.frame = convert(pageRect, from: scrollView)
        slideView.contentSize = contentSize
        slideView.beginSlide(current: capturePage(), back: back, forward: forward)
    }

    func updateSlide(amount: CGFloat) {
        slideView.updateSlide(amount: amount)
    }

    func endSlide() {
        slideView.endSlide()
    }

    /// The scroll view's bounds minus the column header band, in scroll
    /// view coordinates. The header's material background doesn't survive
    /// `cacheDisplay`, so it never goes into a snapshot.
    private var pageRect: NSRect {
        var rect = scrollView.bounds
        guard let headerClip = (scrollView.documentView as? NSTableView)?.headerView?.superview else {
            return rect
        }
        let headerRect = scrollView.convert(headerClip.bounds, from: headerClip).intersection(rect)
        guard !headerRect.isEmpty else { return rect }
        if headerRect.minY <= rect.minY {
            rect.size.height = rect.maxY - headerRect.maxY
            rect.origin.y = headerRect.maxY
        } else {
            rect.size.height = headerRect.minY - rect.minY
        }
        return rect
    }
}
