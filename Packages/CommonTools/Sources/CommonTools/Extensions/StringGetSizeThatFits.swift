// Excerpt from https://github.com/krzyzanowskim/CoreTextWorkshop
// Licence BSD-2 clause
// Marcin Krzyzanowski marcin@krzyzanowskim.com
import Foundation
import CoreText
extension NSAttributedString {
    public func getSizeThatFits(maxWidth: CGFloat) -> CGSize {
        let framesetter = CTFramesetterCreateWithAttributedString(self)
        let rectPath = CGRect(origin: .zero, size: CGSize(width: maxWidth, height: 50000))

        let ctFrame = CTFramesetterCreateFrame(framesetter, CFRange(), CGPath(rect: rectPath, transform: nil), nil)

        guard let ctLines = CTFrameGetLines(ctFrame) as? [CTLine], !ctLines.isEmpty else {
            return .zero
        }

        var ctLinesOrigins = [CGPoint](repeating: .zero, count: ctLines.count)
        // Get origins in CoreGraphics coodrinates
        CTFrameGetLineOrigins(ctFrame, CFRange(), &ctLinesOrigins)

        // Transform last origin to iOS coordinates
        let transform: CGAffineTransform
#if os(macOS)
        transform = CGAffineTransform.identity
#else
        transform = CGAffineTransform(scaleX: 1, y: -1).concatenating(CGAffineTransform(translationX: 0, y: rectPath.height))
#endif

        guard let lastCTLineOrigin = ctLinesOrigins.last?.applying(transform), let lastCTLine = ctLines.last else {
            return .zero
        }

        // Get last line metrics and get full height (relative to from origin)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        CTLineGetTypographicBounds(lastCTLine, &ascent, &descent, &leading)
        let lineSpacing = (floor(ascent + descent + leading) * 0.2) + 0.5 // 20% by default, actual value depends on Paragraph
//        let lineHeight = floor(ascent + descent + leading) + 0.5

        // Calculate maximum height of the frame
        let maxHeight = lastCTLineOrigin.y + descent + leading + (lineSpacing / 2)
        return CGSize(width: maxWidth, height: maxHeight)
    }
}
