import Foundation
import HeidrunUI

/// Pure conversion from `[ChatViewModel.Line]` → `[TranscriptLine]`.
///
/// Lives next to `ChatView` because the projection rules are part of how
/// chat is presented, not part of the wire-level chat model.
public enum ChatTranscriptProjection {
    @MainActor
    public static func lines(
        from chatLines: [ChatViewModel.Line],
        showTimestamps: Bool,
        timestampFormatter: DateFormatter
    ) -> [TranscriptLine] {
        chatLines.map { chatLine in
            TranscriptLine(
                id: chatLine.id.uuidString,
                segments: segments(
                    for: chatLine,
                    showTimestamps: showTimestamps,
                    timestampFormatter: timestampFormatter
                )
            )
        }
    }

    private static func segments(
        for chatLine: ChatViewModel.Line,
        showTimestamps: Bool,
        timestampFormatter: DateFormatter
    ) -> [TranscriptSegment] {
        let stamp = timestampFormatter.string(from: chatLine.receivedAt)

        if chatLine.isSystem {
            return [
                TranscriptSegment(text: stamp, style: .timestamp),
                TranscriptSegment(text: chatLine.body, style: .system)
            ]
        }

        if chatLine.sender == nil {
            var segments: [TranscriptSegment] = []
            if showTimestamps {
                segments.append(TranscriptSegment(text: stamp, style: .timestamp))
            }
            segments.append(TranscriptSegment(text: "* " + chatLine.body, style: .action))
            return segments
        }

        var segments: [TranscriptSegment] = []
        if showTimestamps {
            segments.append(TranscriptSegment(text: stamp, style: .timestamp))
        }
        segments.append(TranscriptSegment(text: chatLine.sender ?? "", style: .sender))
        segments.append(TranscriptSegment(text: ": ", style: .separator))
        segments.append(TranscriptSegment(text: chatLine.body, style: .body))
        return segments
    }
}
