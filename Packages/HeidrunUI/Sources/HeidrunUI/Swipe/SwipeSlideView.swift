import AppKit
import QuartzCore
import CommonTools

/// Safari-style slide of page snapshots during a two-finger back/forward
/// swipe. Hidden and click-through except while sliding; the owner sets
/// its frame to the page area.
public final class SwipeSlideView: NSView {
    /// Density the page currently draws at; kept in sync by the owner.
    public var contentSize = ContentSize.default
    public private(set) var isSliding = false
    private let underLayer = CALayer()
    private let topLayer = CALayer()
    private var currentPage: PageSnapshot?
    private var backPage: PageSnapshot?
    private var forwardPage: PageSnapshot?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isHidden = true
        layer?.masksToBounds = true
        layer?.addSublayer(underLayer)
        layer?.addSublayer(topLayer)
        topLayer.shadowOpacity = 0.25
        topLayer.shadowRadius = 8
        topLayer.shadowOffset = .zero
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override public func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Start a slide. Targets that no longer fit (window resized, light/dark
    /// or density changed since) are dropped; the slide then shows plain
    /// background.
    public func beginSlide(current: PageSnapshot?, back: PageSnapshot?, forward: PageSnapshot?) {
        let pageSize = bounds.size
        currentPage = current
        backPage = back.flatMap { fits($0, size: pageSize) ? $0 : nil }
        forwardPage = forward.flatMap { fits($0, size: pageSize) ? $0 : nil }
        let background = resolvedBackground()
        let scale = window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [underLayer, topLayer] {
            layer.frame = bounds
            layer.backgroundColor = background
            layer.contentsScale = scale
        }
        topLayer.shadowPath = CGPath(rect: CGRect(origin: .zero, size: pageSize), transform: nil)
        CATransaction.commit()
        isSliding = true
        isHidden = false
        updateSlide(amount: 0)
    }

    /// `amount` > 0 moves toward back, < 0 toward forward; ±1 = done.
    /// Back: the current page slides right off the previous one.
    /// Forward: the next page slides in from the right over the current.
    public func updateSlide(amount: CGFloat) {
        guard isSliding else { return }
        let width = bounds.width
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

    public func endSlide() {
        guard isSliding else { return }
        isSliding = false
        isHidden = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        underLayer.contents = nil
        topLayer.contents = nil
        CATransaction.commit()
        currentPage = nil
        backPage = nil
        forwardPage = nil
    }

    private func fits(_ page: PageSnapshot, size pageSize: CGSize) -> Bool {
        page.fits(
            size: pageSize,
            appearance: PageSnapshot.lightOrDark(effectiveAppearance),
            contentSize: contentSize
        )
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
