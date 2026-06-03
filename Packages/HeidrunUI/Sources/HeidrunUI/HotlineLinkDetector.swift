import Foundation

/// Finds clickable URLs inside free-form transcript / news body text.
///
/// Recognised schemes: `hotline://`, `heidrun://`, `http://`, `https://`.
/// The first two route back into the app via `.onOpenURL` →
/// `HotlineURLParser`; the latter two get handed off to the user's
/// default browser by macOS.
public enum HotlineLinkDetector {

    public struct DetectedLink: Equatable {
        public let range: Range<String.Index>
        public let url: URL
    }

    /// Scan `text` and return every clickable URL run, in source order.
    /// Empty array when nothing matches.
    public static func scan(_ text: String) -> [DetectedLink] {
        guard !text.isEmpty else { return [] }
        let matches = pattern.matches(
            in: text,
            options: [],
            range: NSRange(text.startIndex..<text.endIndex, in: text)
        )
        var results: [DetectedLink] = []
        for match in matches {
            guard match.range.location != NSNotFound,
                  var range = Range(match.range, in: text) else { continue }
            // Strip common trailing punctuation that almost always belongs
            // to the surrounding prose, not the URL — `Visit hotline://a.b.`
            // ends at "b", not at "b.".
            while let last = text[range].last, trailingDrops.contains(last) {
                range = range.lowerBound..<text.index(before: range.upperBound)
            }
            let substring = String(text[range])
            guard !substring.isEmpty, let url = URL(string: substring) else { continue }
            results.append(DetectedLink(range: range, url: url))
        }
        return results
    }

    /// Cached regex. NSRegularExpression instances are thread-safe once
    /// compiled; scanning a transcript is read-only.
    ///
    /// Anchored loosely (no word boundary — `(hotline://x)` still matches)
    /// and greedily up to whitespace or any of the angle/quote/paren chars
    /// we don't want inside a URL anyway. A constant literal pattern, so a
    /// compile failure would be a programmer error — trap explicitly.
    private static let pattern: NSRegularExpression = {
        let raw = #"(?i)(?:hotline|heidrun|https?)://[^\s<>"()\[\]]+"#
        do {
            return try NSRegularExpression(pattern: raw, options: [])
        } catch {
            fatalError("HotlineLinkDetector regex pattern is invalid: \(error)")
        }
    }()

    private static let trailingDrops: Set<Character> = [".", ",", ";", ":", "!", "?", ")"]
}
