import Foundation

/// Helpers for the optional emoji avatar (a Heidrun extension to the
/// Hotline user icon). The emoji arrives as a free string on the wire, so
/// rendering defends against peers stuffing text into the field.
public enum EmojiAvatar {
    /// The renderable emoji from a received value: the first grapheme
    /// cluster, or `nil` when the value is empty/blank or exceeds the
    /// 64-byte cap (comfortably holds the longest standard ZWJ emoji).
    public static func sanitized(_ raw: String?) -> String? {
        guard let raw, raw.utf8.count <= 64 else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return nil }
        return String(first)
    }
}
