import AppKit
import QuartzCore
import CommonTools
import HeidrunUI

/// Hosts the file list's scroll view and, during a two-finger swipe, a
/// Safari-style slide of page snapshots above it.
final class FileSwipeContainerView: NSView {
    let scrollView: NSScrollView
    /// Density the table currently draws at; kept in sync by the owner.
    var contentSize = ContentSize.default
    private let overlayView = NSView()
    private let underLayer = CALayer()
    private let topLayer = CALayer()
    private var currentPage: PageSnapshot?
    private var backPage: PageSnapshot?
    private var forwardPage: PageSnapshot?
    private var isSliding = false

    init(scrollView: NSScrollView) {
        self.scrollView = scrollView
        super.init(frame: .zero)
        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)

        overlayView.wantsLayer = true
        overlayView.isHidden = true
        overlayView.layer?.masksToBounds = true
        overlayView.layer?.addSublayer(underLayer)
        overlayView.layer?.addSublayer(topLayer)
        topLayer.shadowOpacity = 0.25
        topLayer.shadowRadius = 8
        topLayer.shadowOffset = .zero
        addSubview(overlayView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Bitmap of the rows area as it looks right now (header excluded).
    func capturePage() -> PageSnapshot? {
        PageSnapshot.capture(of: scrollView, rect: pageRect, contentSize: contentSize)
    }

    /// Start a slide. Targets that no longer fit (window resized, light/dark
    /// or density changed since) are dropped; the slide then shows plain
    /// background.
    func beginSlide(back: PageSnapshot?, forward: PageSnapshot?) {
        let pageFrame = pageRect
        let pageSize = pageFrame.size
        // Cover only the rows; the live column header stays put above.
        overlayView.frame = convert(pageFrame, from: scrollView)
        currentPage = capturePage()
        backPage = back.flatMap { fits($0, size: pageSize) ? $0 : nil }
        forwardPage = forward.flatMap { fits($0, size: pageSize) ? $0 : nil }
        let background = resolvedBackground()
        let scale = window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [underLayer, topLayer] {
            layer.frame = overlayView.bounds
            layer.backgroundColor = background
            layer.contentsScale = scale
        }
        topLayer.shadowPath = CGPath(rect: CGRect(origin: .zero, size: overlayView.bounds.size), transform: nil)
        CATransaction.commit()
        isSliding = true
        overlayView.isHidden = false
        updateSlide(amount: 0)
    }

    /// `amount` > 0 moves toward back, < 0 toward forward; ±1 = done.
    /// Back: the current page slides right off the previous one.
    /// Forward: the next page slides in from the right over the current.
    func updateSlide(amount: CGFloat) {
        guard isSliding else { return }
        let width = overlayView.bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if amount >= 0 {
            underLayer.contents = backPage?.image
            topLayer.contents = currentPage?.image
            topLayer.frame.origin.x = amount * width
        } else {
            underLayer.contents = currentPage?.image
            topLayer.contents = forwardPage?.image
            topLayer.frame.origin.x = (1 + amount) * width
        }
        CATransaction.commit()
    }

    func endSlide() {
        guard isSliding else { return }
        isSliding = false
        overlayView.isHidden = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        underLayer.contents = nil
        topLayer.contents = nil
        CATransaction.commit()
        currentPage = nil
        backPage = nil
        forwardPage = nil
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

    private func fits(_ page: PageSnapshot, size pageSize: CGSize) -> Bool {
        page.fits(size: pageSize, appearance: pageAppearance, contentSize: contentSize)
    }

    /// Light or dark, ignoring vibrancy / high-contrast variants.
    private var pageAppearance: NSAppearance.Name {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
    }

    /// Opaque fill behind the (partly transparent) page bitmaps, in the
    /// view's current light/dark appearance.
    private func resolvedBackground() -> CGColor {
        var color = NSColor.windowBackgroundColor.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            color = NSColor.windowBackgroundColor.cgColor
        }
        return color
    }
}
