import Testing
@testable import HeidrunUI

@Suite("EmojiAvatar.sanitized")
struct EmojiAvatarTests {
    @Test("nil and blank yield nil")
    func blanks() {
        #expect(EmojiAvatar.sanitized(nil) == nil)
        #expect(EmojiAvatar.sanitized("") == nil)
        #expect(EmojiAvatar.sanitized("   ") == nil)
    }

    @Test("keeps only the first grapheme cluster")
    func firstGrapheme() {
        #expect(EmojiAvatar.sanitized("🎸") == "🎸")
        #expect(EmojiAvatar.sanitized("🎸🌮") == "🎸")
        #expect(EmojiAvatar.sanitized("👨‍👩‍👧‍👦") == "👨‍👩‍👧‍👦") // one ZWJ grapheme
    }

    @Test("rejects values over the byte cap")
    func byteCap() {
        let huge = String(repeating: "a", count: 65)
        #expect(EmojiAvatar.sanitized(huge) == nil)
    }
}
