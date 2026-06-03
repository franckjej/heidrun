import Foundation

/// One displayable line in a `SelectableTranscript`.
///
/// A line is an ordered run of styled `TranscriptSegment`s. The builder
/// concatenates segments per `TranscriptAttributedStringBuilder`'s spacing
/// rules and ends every line with a single `\n`.
public struct TranscriptLine: Identifiable, Hashable, Sendable {
    public let id: String
    public let segments: [TranscriptSegment]

    public init(id: String, segments: [TranscriptSegment]) {
        self.id = id
        self.segments = segments
    }
}

/// One styled run within a `TranscriptLine`.
public struct TranscriptSegment: Hashable, Sendable {
    public let text: String
    public let style: TranscriptSegmentStyle

    public init(text: String, style: TranscriptSegmentStyle) {
        self.text = text
        self.style = style
    }
}

/// Semantic role of a segment. The builder maps each style to a fixed
/// font + color combination — callers never deal in raw attributes.
public enum TranscriptSegmentStyle: Sendable, Hashable {
    case timestamp
    case sender
    case separator
    case body
    case action
    case system
}
