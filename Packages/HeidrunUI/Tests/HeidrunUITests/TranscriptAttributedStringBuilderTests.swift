import Foundation
import Testing
@testable import HeidrunUI

@Suite("TranscriptAttributedStringBuilder — plain text")
struct TranscriptAttributedStringBuilderPlainTextTests {

    @Test("normal line with timestamp uses two spaces before sender")
    func normalWithTimestamp() {
        let line = TranscriptLine(id: "1", segments: [
            TranscriptSegment(text: "12:34:56", style: .timestamp),
            TranscriptSegment(text: "Jens", style: .sender),
            TranscriptSegment(text: ": ", style: .separator),
            TranscriptSegment(text: "hello world", style: .body)
        ])

        let plain = TranscriptAttributedStringBuilder.build(lines: [line]).string

        #expect(plain == "12:34:56  Jens: hello world\n")
    }

    @Test("normal line without timestamp has no leading whitespace")
    func normalWithoutTimestamp() {
        let line = TranscriptLine(id: "1", segments: [
            TranscriptSegment(text: "Jens", style: .sender),
            TranscriptSegment(text: ": ", style: .separator),
            TranscriptSegment(text: "hello world", style: .body)
        ])

        let plain = TranscriptAttributedStringBuilder.build(lines: [line]).string

        #expect(plain == "Jens: hello world\n")
    }

    @Test("action line with timestamp")
    func actionWithTimestamp() {
        let line = TranscriptLine(id: "1", segments: [
            TranscriptSegment(text: "12:35:10", style: .timestamp),
            TranscriptSegment(text: "* Jens waves", style: .action)
        ])

        let plain = TranscriptAttributedStringBuilder.build(lines: [line]).string

        #expect(plain == "12:35:10  * Jens waves\n")
    }

    @Test("system line is timestamp + body with two spaces")
    func systemLine() {
        let line = TranscriptLine(id: "1", segments: [
            TranscriptSegment(text: "12:36:00", style: .timestamp),
            TranscriptSegment(text: "--- Bob joined ---", style: .system)
        ])

        let plain = TranscriptAttributedStringBuilder.build(lines: [line]).string

        #expect(plain == "12:36:00  --- Bob joined ---\n")
    }

    @Test("multiple lines are joined with single newlines")
    func multipleLines() {
        let lines = [
            TranscriptLine(id: "1", segments: [
                TranscriptSegment(text: "Jens", style: .sender),
                TranscriptSegment(text: ": ", style: .separator),
                TranscriptSegment(text: "hi", style: .body)
            ]),
            TranscriptLine(id: "2", segments: [
                TranscriptSegment(text: "Anna", style: .sender),
                TranscriptSegment(text: ": ", style: .separator),
                TranscriptSegment(text: "yo", style: .body)
            ])
        ]

        let plain = TranscriptAttributedStringBuilder.build(lines: lines).string

        #expect(plain == "Jens: hi\nAnna: yo\n")
    }

    @Test("empty segments line renders as a single newline (blank line)")
    func emptyLine() {
        let line = TranscriptLine(id: "1", segments: [])

        let plain = TranscriptAttributedStringBuilder.build(lines: [line]).string

        #expect(plain == "\n")
    }

    @Test("body with embedded newlines is preserved verbatim")
    func multilineBody() {
        let line = TranscriptLine(id: "1", segments: [
            TranscriptSegment(text: "first paragraph\nsecond paragraph", style: .body)
        ])

        let plain = TranscriptAttributedStringBuilder.build(lines: [line]).string

        #expect(plain == "first paragraph\nsecond paragraph\n")
    }

    @Test("empty input yields empty string")
    func empty() {
        let plain = TranscriptAttributedStringBuilder.build(lines: []).string
        #expect(plain.isEmpty)
    }

    @Test("body segment with a hotline URL carries an .link attribute on the URL run")
    func linkRunInBody() throws {
        let line = TranscriptLine(id: "1", segments: [
            TranscriptSegment(text: "see hotline://server.example for more", style: .body)
        ])
        let built = TranscriptAttributedStringBuilder.build(lines: [line])
        let plain = built.string

        let urlRange = (plain as NSString).range(of: "hotline://server.example")
        #expect(urlRange.location != NSNotFound)
        let attrs = built.attributes(at: urlRange.location, effectiveRange: nil)
        let url = try #require(attrs[.link] as? URL)
        #expect(url.absoluteString == "hotline://server.example")

        // The surrounding "see " run should NOT carry .link.
        let preAttrs = built.attributes(at: 0, effectiveRange: nil)
        #expect(preAttrs[.link] == nil)
    }
}

import AppKit

@Suite("TranscriptAttributedStringBuilder — attributes")
struct TranscriptAttributedStringBuilderAttributeTests {

    /// Helper: build a single-line transcript with one styled segment and
    /// read back the attributes at index 0.
    private func attributes(
        for style: TranscriptSegmentStyle,
        text: String = "x"
    ) -> [NSAttributedString.Key: Any] {
        let line = TranscriptLine(id: "1", segments: [
            TranscriptSegment(text: text, style: style)
        ])
        let built = TranscriptAttributedStringBuilder.build(lines: [line])
        return built.attributes(at: 0, effectiveRange: nil)
    }

    @Test("timestamp run is italic + monospacedDigit + tertiary color + small size")
    func timestampAttributes() throws {
        let attrs = attributes(for: .timestamp, text: "12:34:56")
        let font = try #require(attrs[.font] as? NSFont)
        #expect(font.pointSize == NSFont.smallSystemFontSize)
        #expect(font.fontDescriptor.symbolicTraits.contains(.italic))
        #expect(attrs[.foregroundColor] as? NSColor == NSColor.tertiaryLabelColor)
    }

    @Test("sender run is semibold + label color + body size")
    func senderAttributes() throws {
        let attrs = attributes(for: .sender, text: "Jens")
        let font = try #require(attrs[.font] as? NSFont)
        #expect(font.pointSize == NSFont.systemFontSize)
        #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(attrs[.foregroundColor] as? NSColor == NSColor.labelColor)
    }

    @Test("separator run is secondary label color")
    func separatorAttributes() {
        let attrs = attributes(for: .separator, text: ": ")
        #expect(attrs[.foregroundColor] as? NSColor == NSColor.secondaryLabelColor)
    }

    @Test("body run is label color + body size + no traits")
    func bodyAttributes() throws {
        let attrs = attributes(for: .body, text: "hello")
        let font = try #require(attrs[.font] as? NSFont)
        #expect(font.pointSize == NSFont.systemFontSize)
        #expect(!font.fontDescriptor.symbolicTraits.contains(.italic))
        #expect(!font.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(attrs[.foregroundColor] as? NSColor == NSColor.labelColor)
    }

    @Test("action run is italic + secondary label + body size")
    func actionAttributes() throws {
        let attrs = attributes(for: .action, text: "* waves")
        let font = try #require(attrs[.font] as? NSFont)
        #expect(font.pointSize == NSFont.systemFontSize)
        #expect(font.fontDescriptor.symbolicTraits.contains(.italic))
        #expect(attrs[.foregroundColor] as? NSColor == NSColor.secondaryLabelColor)
    }

    @Test("system run is italic + secondary label + small size")
    func systemAttributes() throws {
        let attrs = attributes(for: .system, text: "joined")
        let font = try #require(attrs[.font] as? NSFont)
        #expect(font.pointSize == NSFont.smallSystemFontSize)
        #expect(font.fontDescriptor.symbolicTraits.contains(.italic))
        #expect(attrs[.foregroundColor] as? NSColor == NSColor.secondaryLabelColor)
    }
}
