import AppKit
import Foundation
import CommonTools

/// Pure conversion from `[TranscriptLine]` → `NSAttributedString` suitable
/// for an `NSTextView`. No side effects, no AppKit state — safe to call
/// off the main actor.
public enum TranscriptAttributedStringBuilder {
    public static func build(
        lines: [TranscriptLine],
        contentSize: ContentSize = .default
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for line in lines {
            appendLine(line, into: result, contentSize: contentSize)
            result.append(NSAttributedString(string: "\n"))
        }
        return result
    }

    private static func appendLine(
        _ line: TranscriptLine,
        into result: NSMutableAttributedString,
        contentSize: ContentSize
    ) {
        var previous: TranscriptSegmentStyle?
        for segment in line.segments where !segment.text.isEmpty {
            if let gap = spacing(after: previous, before: segment.style) {
                result.append(NSAttributedString(
                    string: gap,
                    attributes: attributes(for: .body, contentSize: contentSize)
                ))
            }
            appendSegment(segment, into: result, contentSize: contentSize)
            previous = segment.style
        }
    }

    /// Append a single segment. For user-authored prose (`.body` / `.action`)
    /// the text is scanned for hotline / heidrun / http(s) URLs and the
    /// matching ranges receive `.link` runs so the read-only NSTextView
    /// will dispatch clicks through NSWorkspace into our `.onOpenURL`.
    private static func appendSegment(
        _ segment: TranscriptSegment,
        into result: NSMutableAttributedString,
        contentSize: ContentSize
    ) {
        let baseAttributes = attributes(for: segment.style, contentSize: contentSize)
        guard segment.style == .body || segment.style == .action else {
            result.append(NSAttributedString(string: segment.text, attributes: baseAttributes))
            return
        }
        let links = HotlineLinkDetector.scan(segment.text)
        guard !links.isEmpty else {
            result.append(NSAttributedString(string: segment.text, attributes: baseAttributes))
            return
        }
        var cursor = segment.text.startIndex
        for link in links {
            if cursor < link.range.lowerBound {
                let pre = String(segment.text[cursor..<link.range.lowerBound])
                result.append(NSAttributedString(string: pre, attributes: baseAttributes))
            }
            var linkAttributes = baseAttributes
            linkAttributes[.link] = link.url
            result.append(NSAttributedString(
                string: String(segment.text[link.range]),
                attributes: linkAttributes
            ))
            cursor = link.range.upperBound
        }
        if cursor < segment.text.endIndex {
            let tail = String(segment.text[cursor..<segment.text.endIndex])
            result.append(NSAttributedString(string: tail, attributes: baseAttributes))
        }
    }

    /// Inter-segment whitespace:
    ///   - after `.timestamp`: two spaces
    ///   - around `.separator`: none (the separator carries its own trailing space)
    ///   - between any other adjacent non-empty segments: one space
    ///   - nothing before the first segment
    private static func spacing(
        after previous: TranscriptSegmentStyle?,
        before next: TranscriptSegmentStyle
    ) -> String? {
        guard let previous else { return nil }
        if previous == .separator || next == .separator { return nil }
        if previous == .timestamp { return "  " }
        return " "
    }

    private static func attributes(
        for style: TranscriptSegmentStyle,
        contentSize: ContentSize
    ) -> [NSAttributedString.Key: Any] {
        let bodyPt = contentSize.bodyPointSize
        let captionPt = contentSize.captionPointSize
        switch style {
        case .timestamp:
            return [
                .font: italicMonoDigit(size: captionPt),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
        case .sender:
            return [
                .font: NSFont.systemFont(ofSize: bodyPt, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        case .separator:
            return [
                .font: NSFont.systemFont(ofSize: bodyPt),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        case .body:
            return [
                .font: NSFont.systemFont(ofSize: bodyPt),
                .foregroundColor: NSColor.labelColor
            ]
        case .action:
            return [
                .font: italic(size: bodyPt),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        case .system:
            return [
                .font: italic(size: captionPt),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        }
    }

    private static func italic(size: CGFloat) -> NSFont {
        let base = NSFont.systemFont(ofSize: size)
        let italicDescriptor = base.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: italicDescriptor, size: size) ?? base
    }

    private static func italicMonoDigit(size: CGFloat) -> NSFont {
        let italicFont = italic(size: size)
        let monoDescriptor = italicFont.fontDescriptor.addingAttributes([
            .featureSettings: [
                [
                    NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                    NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector
                ]
            ]
        ])
        return NSFont(descriptor: monoDescriptor, size: size) ?? italicFont
    }
}
