import AppKit
import CommonTools

/// A rendered page used by the swipe slide.
public struct PageSnapshot {
    public let image: CGImage
    /// Size in points.
    public let size: CGSize
    /// Light or dark — the appearance it was drawn in.
    public let appearance: NSAppearance.Name
    /// Content density + text size the rows were drawn at.
    public let contentSize: ContentSize

    public init(image: CGImage, size: CGSize, appearance: NSAppearance.Name, contentSize: ContentSize) {
        self.image = image
        self.size = size
        self.appearance = appearance
        self.contentSize = contentSize
    }

    /// Whether it can stand in for a page of `pageSize` drawn in
    /// `pageAppearance` at `pageContentSize` (not after a resize, a
    /// light/dark switch or a density change).
    public func fits(
        size pageSize: CGSize,
        appearance pageAppearance: NSAppearance.Name,
        contentSize pageContentSize: ContentSize
    ) -> Bool {
        size == pageSize && appearance == pageAppearance && contentSize == pageContentSize
    }

    /// Bitmap of `pageBounds` (in `view`'s coordinates) as `view` draws now.
    @MainActor
    public static func capture(of view: NSView, rect pageBounds: NSRect, contentSize: ContentSize) -> PageSnapshot? {
        let fullBounds = view.bounds
        guard pageBounds.width > 0, pageBounds.height > 0,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: fullBounds),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return nil }
        // Live text draws unsmoothed; `cacheDisplay` smooths it, which
        // reads as heavier, brighter text during the slide.
        context.cgContext.setShouldSmoothFonts(false)
        // Draw everything, then crop: with a sub-rect, subviews come out
        // shifted by its origin.
        view.displayIgnoringOpacity(fullBounds, in: context)
        let scale = CGFloat(bitmap.pixelsWide) / fullBounds.width
        let topOffset = view.isFlipped
            ? pageBounds.minY - fullBounds.minY
            : fullBounds.maxY - pageBounds.maxY
        let cropRect = CGRect(
            x: (pageBounds.minX - fullBounds.minX) * scale,
            y: topOffset * scale,
            width: pageBounds.width * scale,
            height: pageBounds.height * scale
        ).integral
        guard let image = bitmap.cgImage?.cropping(to: cropRect) else { return nil }
        return PageSnapshot(
            image: image,
            size: pageBounds.size,
            appearance: lightOrDark(view.effectiveAppearance),
            contentSize: contentSize
        )
    }

    /// Light or dark, ignoring vibrancy / high-contrast variants.
    public static func lightOrDark(_ appearance: NSAppearance) -> NSAppearance.Name {
        appearance.bestMatch(from: [.aqua, .darkAqua]) ?? .aqua
    }
}
