import Foundation
import HeidrunUI

/// Pure conversion from a plain-news post array (`[String]`) →
/// `[TranscriptLine]`. Each post becomes one body line; between posts
/// a blank `TranscriptLine` (segments empty) is inserted for visual
/// separation and clipboard readability.
public enum NewsPostsTranscriptProjection {
    public static func lines(from posts: [String]) -> [TranscriptLine] {
        guard !posts.isEmpty else { return [] }
        var result: [TranscriptLine] = []
        for (index, post) in posts.enumerated() {
            result.append(
                TranscriptLine(
                    id: "post-\(index)",
                    segments: [TranscriptSegment(text: post, style: .body)]
                )
            )
            if index < posts.count - 1 {
                result.append(
                    TranscriptLine(id: "blank-after-\(index)", segments: [])
                )
            }
        }
        return result
    }
}
