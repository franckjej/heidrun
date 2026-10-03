import AppKit
import QuartzCore

/// A rendered file-list page used by the swipe slide.
struct PageSnapshot {
    let image: CGImage
    /// Size in points.
    let size: CGSize
    /// Light or dark — the appearance it was drawn in.
    let appearance: NSAppearance.Name

    /// Whether it can stand in for a page of `pageSize` drawn in
    /// `pageAppearance` (not after a resize or a light/dark switch).
    func fits(size pageSize: CGSize, appearance pageAppearance: NSAppearance.Name) -> Bool {
        size == pageSize && appearance == pageAppearance
    }
}

/// Hosts the file list's scroll view and, during a two-finger swipe, a
/// Safari-style slide of page snapshots above it.
final class FileSwipeContainerView: NSView {
    let scrollView: NSScrollView
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

        overlayView.frame = bounds
        overlayView.autoresizingMask = [.width, .height]
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

    /// Bitmap of the scroll view as it looks right now.
    func capturePage() -> PageSnapshot? {
        let pageBounds = scrollView.bounds
        guard pageBounds.width > 0, pageBounds.height > 0,
              let bitmap = scrollView.bitmapImageRepForCachingDisplay(in: pageBounds)
        else { return nil }
        scrollView.cacheDisplay(in: pageBounds, to: bitmap)
        guard let image = bitmap.cgImage else { return nil }
        return PageSnapshot(image: image, size: pageBounds.size, appearance: pageAppearance)
    }

    /// Start a slide. Targets that no longer fit (window resized or
    /// light/dark switched since) are dropped; the slide then shows plain
    /// background.
    func beginSlide(back: PageSnapshot?, forward: PageSnapshot?) {
        let pageSize = scrollView.bounds.size
        currentPage = capturePage()
        backPage = back.flatMap { $0.fits(size: pageSize, appearance: pageAppearance) ? $0 : nil }
        forwardPage = forward.flatMap { $0.fits(size: pageSize, appearance: pageAppearance) ? $0 : nil }
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
