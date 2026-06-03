import Foundation
import HeidrunUI

/// Pure conversion from `[MessagesViewModel.Message]` → `[TranscriptLine]`.
/// Outgoing messages use `ownNickname` as the sender; incoming messages
/// use `peerNickname`. Timestamps are always shown — matches the
/// per-bubble caption behavior of the previous layout.
public enum MessagesTranscriptProjection {
    @MainActor
    public static func lines(
        from messages: [MessagesViewModel.Message],
        ownNickname: String,
        peerNickname: String,
        timestampFormatter: DateFormatter
    ) -> [TranscriptLine] {
        messages.map { message in
            let stamp = timestampFormatter.string(from: message.receivedAt)
            let sender = message.direction == .outgoing ? ownNickname : peerNickname
            return TranscriptLine(
                id: message.id.uuidString,
                segments: [
                    TranscriptSegment(text: stamp, style: .timestamp),
                    TranscriptSegment(text: sender, style: .sender),
                    TranscriptSegment(text: ": ", style: .separator),
                    TranscriptSegment(text: message.text, style: .body)
                ]
            )
        }
    }
}
